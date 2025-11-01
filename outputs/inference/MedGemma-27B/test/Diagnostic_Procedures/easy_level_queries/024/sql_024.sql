WITH PatientInfo AS (
  SELECT
    subject_id
  FROM patients
  WHERE
    gender = 'F' AND anchor_age = 63
),
ProcedureCounts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_procedure_count
  FROM PatientInfo AS p
  JOIN procedures_icd AS proc
    ON p.subject_id = proc.subject_id
  WHERE
    proc.icd_code IN ('33201', '33202', '33203', '33204', '33205', '33206', '33207', '33208', '33209', '33210', '33211', '33212', '33213', '33214', '33215', '33216', '33217', '33218', '33219', '33220', '33221', '33222', '33223', '33224', '33225', '33226', '33227', '33228', '33229', '33230', '33231', '33232', '33233', '33234', '33235', '33236', '33237', '33238', '33239', '33240', '33241', '33242', '33243', '33244', '33245', '33246', '33247', '33248', '33249', '33250', '33251', '33252', '33253', '33254', '33255', '33256', '33257', '33258', '33259', '33260', '33261', '33262', '33263', '33264', '33265', '33266', '33267', '33268', '33269', '33270', '33271', '33272', '33273', '33274', '33275', '33276', '33277', '33278', '33279', '33280', '33281', '33282', '33283', '33284', '33285', '33286', '33287', '33288', '33289', '33290', '33291', '33292', '33293', '33294', '33295', '33296', '33297', '33298', '33299')
),
PercentileCalculation AS (
  SELECT
    PERCENTILE_CONT(distinct_procedure_count, 0.75) AS percentile_75
  FROM ProcedureCounts
)
SELECT
  percentile_75
FROM PercentileCalculation;