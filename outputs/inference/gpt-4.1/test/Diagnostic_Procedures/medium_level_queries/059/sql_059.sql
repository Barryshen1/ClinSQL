WITH hf_admissions AS (
  -- Identify admissions for men age 67-77 with heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender,
    MIN(diag.seq_num) AS min_seq_num, -- lowest seq_num for HF diagnosis
    CASE
      WHEN MIN(diag.seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS hf_type,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    -- Heart failure ICD codes: 428.x (ICD-9), I50.x (ICD-10)
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 67 AND 77
      AND (
        (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
      )
  GROUP BY
    adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime,
    adm.hospital_expire_flag, pat.anchor_age, pat.gender
),
imaging_orders AS (
  -- Imaging studies per admission
  SELECT
    poe.subject_id,
    poe.hadm_id,
    COUNT(DISTINCT poe.poe_id) AS imaging_count
  FROM
    physionet-data.mimiciv_3_1_hosp.poe poe
    -- Imaging orders: order_type contains 'Radiology' or 'Imaging'
  WHERE
    LOWER(poe.order_type) LIKE '%radiology%'
    OR LOWER(poe.order_type) LIKE '%imaging%'
  GROUP BY
    poe.subject_id, poe.hadm_id
),
admission_imaging AS (
  -- Merge imaging counts with HF admissions
  SELECT
    hfa.subject_id,
    hfa.hadm_id,
    hfa.los_days,
    CASE
      WHEN hfa.los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN hfa.los_days BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_bin,
    hfa.hf_type,
    COALESCE(io.imaging_count, 0) AS imaging_count
  FROM
    hf_admissions hfa
    LEFT JOIN imaging_orders io
      ON hfa.subject_id = io.subject_id AND hfa.hadm_id = io.hadm_id
  WHERE
    hfa.los_days BETWEEN 1 AND 7
)
SELECT
  los_bin,
  hf_type,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75,
  COUNT(*) AS n_admissions
FROM
  admission_imaging
WHERE
  los_bin IS NOT NULL
GROUP BY
  los_bin, hf_type
ORDER BY
  los_bin, hf_type;