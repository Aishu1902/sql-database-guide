--PAYROLL DATA2
--UPLOADED THE TABLE USING FLAT FILE 
--TABLE NAME--
SELECT * FROM DC3_AH_EMPLOYEE_PAYROLL order by Employee_Identifier


--Q1: December - February
--Q2: March - May
--Q3: June - August
--Q4: September - November

--TOTAL NO OF RECORDS 234299--
SELECT TOP 1 COUNT(*) OVER()
FROM DC3_AH_EMPLOYEE_PAYROLL

--CHECKING IF ANY COLUMN HAS NULL VALUES--
SELECT 
  SUM(CASE WHEN Fiscal_Year IS NULL THEN 1 ELSE 0 END) AS Fiscal_Year_NULLs,
  SUM(CASE WHEN Fiscal_Quarter IS NULL THEN 1 ELSE 0 END) AS Fiscal_Quarter_NULLs,
  SUM(CASE WHEN Fiscal_Period IS NULL THEN 1 ELSE 0 END) AS Fiscal_Period_NULLs,
  SUM(CASE WHEN First_Name IS NULL THEN 1 ELSE 0 END) AS First_Name_NULLs,
  SUM(CASE WHEN Last_Name IS NULL THEN 1 ELSE 0 END) AS Last_Name_NULLs,
  SUM(CASE WHEN Middle_Init IS NULL THEN 1 ELSE 0 END) AS Middle_Init_NULLs,
  SUM(CASE WHEN Bureau IS NULL THEN 1 ELSE 0 END) AS Bureau_NULLs,
  SUM(CASE WHEN Office IS NULL THEN 1 ELSE 0 END) AS Office_NULLs,
  SUM(CASE WHEN Office_Name IS NULL THEN 1 ELSE 0 END) AS Office_Name_NULLs,
  SUM(CASE WHEN Job_Code IS NULL THEN 1 ELSE 0 END) AS Job_Code_NULLs,
  SUM(CASE WHEN Job_Title IS NULL THEN 1 ELSE 0 END) AS Job_Title_NULLs,
  SUM(CASE WHEN Base_Pay IS NULL THEN 1 ELSE 0 END) AS Base_Pay_NULLs,
  SUM(CASE WHEN Position_ID IS NULL THEN 1 ELSE 0 END) AS Position_ID_NULLs,
  SUM(CASE WHEN Employee_Identifier IS NULL THEN 1 ELSE 0 END) AS Employee_Identifier_NULLs,
  SUM(CASE WHEN Original_Hire_Date IS NULL THEN 1 ELSE 0 END) AS Original_Hire_Date_NULLs
FROM DC3_AH_EMPLOYEE_PAYROLL;


--UPDATING THE REQUIRED COLUMNS ALONE TO UNKNOWN
UPDATE DC3_AH_EMPLOYEE_PAYROLL
SET Office = '0000', Office_Name = 'UNKNOWN OFFICE',Base_Pay='0000'
WHERE Office IS NULL OR Office_Name IS NULL;


--indexing
--CLUSTERD AND NON CLUSTERD
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT 
    Employee_Identifier,
    First_Name,
    Last_Name,
    SUM(Base_Pay) AS Total_Pay_Q1_Q4
FROM DC3_AH_EMPLOYEE_PAYROLL
WHERE Fiscal_Period ='2016Q1' OR Fiscal_Period LIKE '2017Q4'
GROUP BY Employee_Identifier, First_Name, Last_Name
ORDER BY Total_Pay_Q1_Q4 DESC;

CREATE CLUSTERED INDEX IX_CLUSTER_FiscalPeriod
ON DC3_AH_EMPLOYEE_PAYROLL (Fiscal_Period);

--Drop  INDEX IX_CLUSTER_FiscalPeriod ON DC3_AH_EMPLOYEE_PAYROLL

CREATE NONCLUSTERED INDEX idx_emp_lastname
ON DC3_AH_EMPLOYEE_PAYROLL (Last_Name);

--hints
--no lock (if a person is doing changes in the table that wont stop this query from
--processing
SELECT * FROM DC3_AH_EMPLOYEE_PAYROLL WITH (NOLOCK)
WHERE Fiscal_Period LIKE '%Q1';

 SELECT * FROM DC3_AH_EMPLOYEE_PAYROLL WHERE First_Name='James' and Last_Name='ANICHINI';


--lag function+cte
--salary status of employees
WITH task AS (
  SELECT 
    First_Name, 
    Last_Name, 
    Fiscal_Year, 
    ROUND(SUM(Base_Pay), 2) AS Total_Sal
  FROM DC3_AH_EMPLOYEE_PAYROLL
  GROUP BY First_Name, Last_Name, Fiscal_Year
),
lag_calc AS (
  SELECT 
    *,
    LAG(Total_Sal) OVER (
      PARTITION BY First_Name, Last_Name 
      ORDER BY Fiscal_Year
    ) AS Prev_Year_Sal
  FROM task
)
SELECT 
  First_Name,
  Last_Name,
  Fiscal_Year,
  Total_Sal,
  Prev_Year_Sal,
  CASE 
    WHEN Prev_Year_Sal IS NULL THEN null
    ELSE round(Total_Sal - Prev_Year_Sal,2)
  END AS Salary_Change,
    CASE 
    WHEN Prev_Year_Sal IS NULL THEN null
    when round(Total_Sal - Prev_Year_Sal,2)<0 then 'reduced'
	when round(Total_Sal - Prev_Year_Sal,2)>0 then 'increased'
	when round(Total_Sal - Prev_Year_Sal,2)=0 then 'same'
  END AS salary_status
FROM lag_calc
ORDER BY Last_Name, First_Name, Fiscal_Year;

--Average Employee Pay and Headcount by Fiscal Quarter(Inline)
--inline (subquery is in from)
--subquery inside from runs independently of the outer query.
SELECT 
  Fiscal_Year,
  Fiscal_Quarter,
  ROUND(AVG(Base_Pay), 2) AS Avg_Quarterly_Pay,
  COUNT(DISTINCT Employee_Identifier) AS Employees_Count
FROM (
  SELECT 
    Fiscal_Year,
    Fiscal_Quarter,
    Employee_Identifier,
    SUM(Base_Pay) AS Base_Pay
  FROM DC3_AH_EMPLOYEE_PAYROLL
  GROUP BY Fiscal_Year, Fiscal_Quarter, Employee_Identifier
) AS q
GROUP BY Fiscal_Year, Fiscal_Quarter
ORDER BY Fiscal_Year, Fiscal_Quarter;

--Employees Who Changed Office IDs Across Years
WITH yearly_office AS (
  SELECT 
    Employee_Identifier,
    First_Name,
    Last_Name,
    Fiscal_Year,
    Office,
    ROW_NUMBER() OVER (
      PARTITION BY Employee_Identifier, Fiscal_Year 
      ORDER BY Base_Pay DESC 
    ) AS rn
  FROM DC3_AH_EMPLOYEE_PAYROLL
),
office_history AS (
  SELECT 
    Employee_Identifier,
    First_Name,
    Last_Name,
    Fiscal_Year,
    Office AS Current_Office,
    LAG(Office) OVER (
      PARTITION BY Employee_Identifier
      ORDER BY Fiscal_Year
    ) AS Previous_Office
  FROM yearly_office
  WHERE rn = 1
),
office_change_detected AS (
  SELECT *,
         CASE 
           WHEN Previous_Office IS NOT NULL AND Previous_Office <> Current_Office 
           THEN 'CHANGED'
           ELSE 'NO CHANGE'
         END AS Office_Change_Status
  FROM office_history
)
SELECT *
FROM office_change_detected
WHERE Office_Change_Status = 'CHANGED'
ORDER BY Last_Name, First_Name, Fiscal_Year;


--Dynamic SQL+Pivot

DECLARE @sql nvarchar(max)
DECLARE @col nvarchar(max)
SELECT @col='SELECT '

DECLARE @columns NVARCHAR(MAX), @sql NVARCHAR(MAX);

-- Step 1: Get distinct quarters to use as pivot columns
SELECT @columns = STRING_AGG(QUOTENAME(Fiscal_Quarter), ', ')
FROM (SELECT DISTINCT [Fiscal_Quarter] FROM DC3_AH_EMPLOYEE_PAYROLL) AS q;

-- Step 2: Build the dynamic SQL with PIVOT
SET @sql = '
SELECT *
FROM (
    SELECT 
        [last_name],
        [Fiscal_Quarter],
        [BASE_PAY]
    FROM 
        DC3_AH_EMPLOYEE_PAYROLL
) AS SourceTable
PIVOT (
    SUM(BASE_PAY)
    FOR Fiscal_Quarter IN (' + @columns + ')
) AS PivotTable;
';

-- Step 3: Execute the dynamic SQL
EXEC sp_executesql @sql;

