WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 38 AND 48
    AND p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'E11%'
        AND d.icd_version = 10
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I50%'
        AND d.icd_version = 10
    )
),
admissions_cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort c ON a.hadm_id = c.hadm_id
),
first_period AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN p.drug_type = 'insulin' AND p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL '72' HOUR THEN 1 ELSE 0 END) AS insulin_first,
         MAX(CASE WHEN p.drug_type = 'oral' AND p.starttime BETWEEN a.admittime AND a.admittime + INTERVAL '72' HOUR THEN 1 ELSE 0 END) AS oral_first
  FROM admissions_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
),
last_period AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN p.drug_type = 'insulin' AND p.starttime BETWEEN a.dischtime - INTERVAL '72' HOUR AND a.dischtime THEN 1 ELSE 0 END) AS insulin_last,
         MAX(CASE WHEN p.drug_type = 'oral' AND p.starttime BETWEEN a.dischtime - INTERVAL '72' HOUR AND a.dischtime THEN 1 ELSE 0 END) AS oral_last
  FROM admissions_cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id
)
SELECT 
  AVG(insulin_first) * 100 AS insulin_first_pct,
  AVG(oral_first) * 100 AS oral_first_pct,
  AVG(insulin_last) * 100 AS insulin_last_pct,
  AVG(oral_last) * 100 AS oral_last_pct
FROM first_period fp
JOIN last_period lp ON fp.hadm_id = lp.hadm_id;