WITH HF_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I50%' -- Heart Failure ICD-10 codes
    AND a.admission_type = 'EMERGENCY' -- Assuming HF admissions are often emergency
    -- AND a.gender = 'M' -- Male patients - This column is in the patients table, not admissions
    -- AND a.anchor_age = 66 -- Specific age - This column is in the patients table, not admissions
  GROUP BY
    a.subject_id,
    a.hadm_id
),
First24h_Creatinine AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum AS creatinine_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine'
    AND le.hadm_id IN (
      SELECT
        hadm_id
      FROM HF_Admissions
    )
    AND le.charttime BETWEEN (
      SELECT
        a.admittime
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.hadm_id = le.hadm_id
    ) AND (
      SELECT
        DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      WHERE
        a.hadm_id = le.hadm_id
    )
)
SELECT
  MAX(creatinine_value) AS max_creatinine
FROM First24h_Creatinine;