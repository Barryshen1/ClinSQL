WITH PatientDiagnosis AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    d.icd_code IN ('E11', 'E11.9', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8') -- T2DM codes
    OR d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.6', 'I50.8', 'I50.9') -- HF codes
), PatientDiagnosisFiltered AS (
  SELECT
    subject_id
  FROM
    PatientDiagnosis
  WHERE
    gender = 'F'
    AND age BETWEEN 48 AND 58
  GROUP BY
    subject_id
  HAVING
    COUNT(DISTINCT icd_code) >= 2 -- Ensure both T2DM and HF are present
), MedicationOrders AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    p.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%semaglutide%'
    OR p.drug LIKE '%dulaglutide%'
    OR p.drug LIKE '%liraglutide%'
    OR p.drug LIKE '%exenatide%'
    OR p.drug LIKE '%lixisenatide%'
    OR p.drug LIKE '%taspoglutide%'
    OR p.drug LIKE '%tirzepatide%'
    OR p.drug LIKE '%dapagliflozin%'
    OR p.drug LIKE '%empagliflozin%'
    OR p.drug LIKE '%canagliflozin%'
    OR p.drug LIKE '%ertugliflozin%'
    OR p.drug LIKE '%sotagliflozin%'
    OR p.drug LIKE '%insulin%' -- Include insulin as a comparator
)
SELECT
  CASE
    WHEN a.starttime < TIMESTAMP_SUB(a.admittime, INTERVAL 72 HOUR)
    THEN 'First 72h'
    ELSE 'Last 48h'
  END AS time_window,
  COUNT(DISTINCT a.subject_id) * 100.0 / COUNT(DISTINCT a.subject_id) AS initiation_rate_percent,
  COUNT(DISTINCT a.subject_id) AS initiation_count,
  (
    SUM(CASE WHEN a.starttime < TIMESTAMP_SUB(a.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) - SUM(CASE WHEN a.starttime >= TIMESTAMP_SUB(a.admittime, INTERVAL 72 HOUR) AND a.starttime < TIMESTAMP_SUB(a.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END)
  ) AS absolute_difference_pp
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
  PatientDiagnosisFiltered AS pdf
  ON a.subject_id = pdf.subject_id
JOIN
  MedicationOrders AS mo
  ON a.subject_id = mo.subject_id AND a.hadm_id = mo.hadm_id
WHERE
  mo.route = 'subcutaneous'
  AND mo.drug LIKE '%semaglutide%'
  OR mo.drug LIKE '%dulaglutide%'
  OR mo.drug LIKE '%liraglutide%'
  OR mo.drug LIKE '%exenatide%'
  OR mo.drug LIKE '%lixisenatide%'
  OR mo.drug LIKE '%taspoglutide%'
  OR mo.drug LIKE '%tirzepatide%'
GROUP BY
  time_window
ORDER BY
  time_window;