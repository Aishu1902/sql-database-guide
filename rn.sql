--PAYROLL DATA1
select * from dc3_ah_dept_new;--DEPARTMENTID - FK(EMP),PK
select * from dc3_ah_emp_new; --EMPLOYEEID - PK ,DEPARTMENTID - FK(DEPT)
select * from dc3_ah_performance;--REVIEWID-PF, EMPLOYEEID - FK(EMP)
select * from dc3_ah_salary;--SALARYID-PF, EMPLOYEEID - FK(EMP)


ALTER TABLE dc3_ah_emp_new
ADD CONSTRAINT PK_Employee PRIMARY KEY (EmployeeID);

--row number calculation
--based on department
SELECT 
    E.EmployeeID,
    E.DepartmentID,
    D.DepartmentName,
    ROW_NUMBER() OVER (PARTITION BY E.DepartmentID ORDER BY E.JoiningDate) AS RN
FROM dc3_ah_emp_new E
JOIN dc3_ah_dept_new D ON E.DepartmentID = D.DepartmentID;


--DEDUPING
WITH RankedEmployees AS (
  SELECT *,
         ROW_NUMBER() OVER (
           PARTITION BY FirstName, LastName, DepartmentID
           ORDER BY JoiningDate ASC
         ) AS rn
  FROM dc3_ah_emp_new
)
SELECT * FROM RankedEmployees WHERE rn = 1; --REMOVES DUPLICATES

--If you want to delete it 
--DELETE FROM dc3_ah_emp_new
--WHERE EmployeeID IN (
--    SELECT EmployeeID
--    FROM RankedEmployees
--    WHERE rn > 1
--);

--USING ROWNUMBER TO CHECK DEDUPING OF ANOTHER CASE
SELECT 
    S.SalaryID,
    S.EmployeeID,
    E.FirstName,
    S.BaseSalary,
    S.EffectiveFrom,
    ROW_NUMBER() OVER (
        PARTITION BY S.EmployeeID 
        ORDER BY S.EffectiveFrom DESC
    ) AS rn
FROM dc3_ah_salary S
JOIN dc3_ah_emp_new E ON S.EmployeeID = E.EmployeeID;



--pagination
WITH numbered_employees AS (
  SELECT 
    FirstName,
    LastName,
    Salary,
    ROW_NUMBER() OVER (ORDER BY LastName) AS row_num
  FROM dc3_ah_emp_new
)
SELECT *
FROM numbered_employees
WHERE row_num BETWEEN 6 AND 10;



--DIFF B/W RANK,ROW_NUMBER,DENSE_RANK
--RN IS FAST
SELECT 
    E.FirstName,
    D.DepartmentName,
    S.BaseSalary,
    RANK() OVER (
        PARTITION BY E.DepartmentID 
        ORDER BY S.BaseSalary DESC
    ) AS SalaryRank,
	 ROW_NUMBER() OVER (
        PARTITION BY E.DepartmentID 
        ORDER BY S.BaseSalary DESC
    ) AS SalaryRownum,
	 DENSE_RANK() OVER (
        PARTITION BY E.DepartmentID 
        ORDER BY S.BaseSalary DESC
    ) AS SalaryDenseRank
FROM dc3_ah_emp_new E
JOIN dc3_ah_dept_new D ON E.DepartmentID = D.DepartmentID
JOIN dc3_ah_salary S ON E.EmployeeID = S.EmployeeID;

--CONSTRAINTS
CREATE TABLE dc3_ah_attendance (
    AttendanceID INT PRIMARY KEY,                             -- PRIMARY KEY
    EmployeeID INT NOT NULL,                                  -- FOREIGN KEY + NOT NULL
    AttendanceDate DATE NOT NULL,                             -- NOT NULL
    Status VARCHAR(20) DEFAULT 'Present' CHECK (Status IN ('Present', 'Absent', 'Leave')),  -- CHECK + DEFAULT
    InTime TIME,
    OutTime TIME,
    
    CONSTRAINT FK_Attendance_Emp FOREIGN KEY (EmployeeID) REFERENCES dc3_ah_emp_new(EmployeeID),--referential integrity
    
    CONSTRAINT UQ_Emp_Date UNIQUE (EmployeeID, AttendanceDate)  -- UNIQUE (1 record per employee per day)
);

--referential integrity
--insert update delete
--FOREIGN KEY (child_column)
--REFERENCES parent_table(parent_column)
--ON DELETE [CASCADE | SET NULL | SET DEFAULT | NO ACTION | RESTRICT]
--ON UPDATE [CASCADE | SET NULL | SET DEFAULT | NO ACTION | RESTRICT];

---INSERT THE VALUES INTO IT
select * from dc3_ah_attendance

--1st joined employee in each department
WITH RankedEmployees AS (
  SELECT 
      E.EmployeeID,
      E.DepartmentID,
      D.DepartmentName,
      ROW_NUMBER() OVER (
          PARTITION BY E.DepartmentID 
          ORDER BY E.JoiningDate
      ) AS RN
  FROM dc3_ah_emp_new E
  JOIN dc3_ah_dept_new D 
      ON E.DepartmentID = D.DepartmentID
)
SELECT * 
FROM RankedEmployees
WHERE RN = 1;


--max,min,first_value,last_value
WITH MaxSalCTE AS (
  SELECT 
    DepartmentID,
    FirstName + ' ' + LastName AS Max_Salary_Name,
    ROW_NUMBER() OVER (
      PARTITION BY DepartmentID 
      ORDER BY TRY_CAST(Salary AS FLOAT) DESC
    ) AS rn
  FROM dc3_ah_emp_new
),
MinSalCTE AS (
  SELECT 
    DepartmentID,
    FirstName + ' ' + LastName AS Min_Salary_Name,
    ROW_NUMBER() OVER (
      PARTITION BY DepartmentID 
      ORDER BY TRY_CAST(Salary AS FLOAT) ASC
    ) AS rn
  FROM dc3_ah_emp_new
),
JoinersCTE AS (
  SELECT 
    DepartmentID,
    FIRST_VALUE(FirstName + ' ' + LastName) OVER (
      PARTITION BY DepartmentID 
      ORDER BY JoiningDate ASC
    ) AS First_Joiner_Name,
    LAST_VALUE(FirstName + ' ' + LastName) OVER (
      PARTITION BY DepartmentID 
      ORDER BY JoiningDate ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS Last_Joiner_Name,
    ROW_NUMBER() OVER (
      PARTITION BY DepartmentID 
      ORDER BY JoiningDate ASC
    ) AS rn
  FROM dc3_ah_emp_new
)

SELECT 
  m.DepartmentID,
  m.Max_Salary_Name,
  n.Min_Salary_Name,
  j.First_Joiner_Name,
  j.Last_Joiner_Name
FROM MaxSalCTE m
JOIN MinSalCTE n ON m.DepartmentID = n.DepartmentID AND n.rn = 1
JOIN JoinersCTE j ON m.DepartmentID = j.DepartmentID AND j.rn = 1
WHERE m.rn = 1;

--SUBQUERY
--salary is greater than the average salary of their department.

--1ST SEE THE AVG SAL OF EACH DEPT
SELECT DepartmentID,ROUND(AVG(TRY_CAST(Salary AS FLOAT)),2) AS AvgSalary
FROM dc3_ah_emp_new
GROUP BY DepartmentID;

--NOW SELECT EMPLOYEES
--correlated 
SELECT FirstName, Salary, DepartmentID
FROM dc3_ah_emp_new e1
WHERE Salary > (
    SELECT AVG(TRY_CAST(Salary AS FLOAT))
    FROM dc3_ah_emp_new  e2
    WHERE e1.DepartmentID = e2.DepartmentID
);
--TOP 2 HIGHEST PAID EMPLOYEES
WITH RankedSalaries AS (
    SELECT 
        E.EmployeeID,
        E.FirstName,
        E.DepartmentID,
        D.DepartmentName,
        S.BaseSalary,
        ROW_NUMBER() OVER (
            PARTITION BY E.DepartmentID 
            ORDER BY S.BaseSalary DESC
        ) AS rn
    FROM 
        dc3_ah_emp_new E 
    JOIN 
        dc3_ah_salary S ON E.EmployeeID = S.EmployeeID
    JOIN 
        dc3_ah_dept_new D ON E.DepartmentID = D.DepartmentID
)
SELECT 
    EmployeeID,
    FirstName,
    DepartmentID,
    DepartmentName,
    BaseSalary
FROM 
    RankedSalaries
WHERE 
    rn <= 2;

-- corelated subquery
--inner query is dependent on outer query
SELECT EmployeeID, FirstName, DepartmentID, Salary
FROM dc3_ah_emp_new E
WHERE (
    SELECT COUNT(*)
    FROM dc3_ah_emp_new
    WHERE DepartmentID = E.DepartmentID
) > 5;

--normal subquery
--subquery inside where runs independently of the outer query.
SELECT EmployeeID, FirstName, DepartmentID, Salary
FROM dc3_ah_emp_new
WHERE DepartmentID = (
    SELECT TOP 1 DepartmentID
    FROM dc3_ah_emp_new
    GROUP BY DepartmentID
    ORDER BY COUNT(*) DESC
);

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
--NOnClustered Index
CREATE NONCLUSTERED INDEX IX_CLUSTER_Emp
ON dc3_ah_emp_new (LASTName);

select EmployeeID from dc3_ah_emp_new where LASTName='Davis';


