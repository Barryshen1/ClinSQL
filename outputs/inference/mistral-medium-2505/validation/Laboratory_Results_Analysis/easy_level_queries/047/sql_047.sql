WITH hf_admissions AS (
  -- Get admissions for male patients aged 66 with heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 66
    AND (
      -- ICD-9 codes for heart failure (428.x)
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      -- ICD-10 codes for heart failure (I50.x)
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),

creatinine_first_24h AS (
  -- Get serum creatinine values in the first 24 hours of admission
  SELECT
    l.subject_id,
    l.hadm_id,
    MAX(l.valuenum) AS max_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    hf_admissions hf
    ON l.subject_id = hf.subject_id AND l.hadm_id = hf.hadm_id
  WHERE
    l.itemid = 50912 -- Serum creatinine
    AND l.charttime BETWEEN hf.admittime
      AND TIMESTAMP_ADD(hf.admittime, INTERVAL 24 HOUR)
  GROUP BY
    l.subject_id, l.hadm_id
)

-- Final result: maximum admission (first 24h) serum creatinine among male HF admissions
SELECT
  MAX(max_creatinine) AS max_admission_creatinine
FROM
  creatinine_first_24h;