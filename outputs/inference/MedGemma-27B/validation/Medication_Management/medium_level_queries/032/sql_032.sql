WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND d.icd_code IN ('E11', 'E10', 'E13', 'E14') -- Diabetes codes
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      WHERE
        d2.subject_id = p.subject_id
        AND d2.icd_code IN ('I50', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9') -- Acute heart failure codes
    )
),
InsulinRegimens AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.charttime,
    CASE
      WHEN LOWER(p.medication) LIKE '%basal-bolus%'
      OR LOWER(p.medication) LIKE '%basal bolus%' THEN 'Basal-Bolus'
      WHEN LOWER(p.medication) LIKE '%basal%' THEN 'Basal'
      WHEN LOWER(p.medication) LIKE '%bolus%' THEN 'Bolus'
      WHEN LOWER(p.medication) LIKE '%sliding scale%'
      OR LOWER(p.medication) LIKE '%sliding-scale%' THEN 'Sliding-Scale'
      ELSE NULL
    END AS regimen_type
  FROM `physionet-data.mimiciv_3_1_hosp.emar` AS p
  WHERE
    p.medication LIKE '%insulin%'
),
TimeWindows AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    a.admittime,
    a.dischtime,
    ir.charttime,
    ir.regimen_type
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON pc.subject_id = a.subject_id AND pc.hadm_id = a.hadm_id
  JOIN InsulinRegimens AS ir
    ON pc.subject_id = ir.subject_id AND pc.hadm_id = ir.hadm_id
  WHERE
    ir.charttime BETWEEN a.admittime AND a.dischtime
),
First24h AS (
  SELECT
    tw.subject_id,
    tw.hadm_id,
    tw.regimen_type
  FROM TimeWindows AS tw
  WHERE
    tw.charttime BETWEEN tw.admittime AND TIMESTAMP_ADD(tw.admittime, INTERVAL 24 HOUR)
),
Final12h AS (
  SELECT
    tw.subject_id,
    tw.hadm_id,
    tw.regimen_type
  FROM TimeWindows AS tw
  WHERE
    tw.charttime BETWEEN TIMESTAMP_SUB(tw.dischtime, INTERVAL 12 HOUR) AND tw.dischtime
)
SELECT
  f24.regimen_type,
  COUNT(DISTINCT f24.subject_id) AS count_first_24h,
  COUNT(DISTINCT f12.subject_id) AS count_final_12h,
  (COUNT(DISTINCT f24.subject_id) - COUNT(DISTINCT f12.subject_id)) / COUNT(DISTINCT f24.subject_id) AS percentage_point_change
FROM First24h AS f24
LEFT JOIN Final12h AS f12
  ON f24.subject_id = f12.subject_id AND f24.regimen_type = f12.regimen_type
GROUP BY
  f24.regimen_type
ORDER BY
  f24.regimen_type;