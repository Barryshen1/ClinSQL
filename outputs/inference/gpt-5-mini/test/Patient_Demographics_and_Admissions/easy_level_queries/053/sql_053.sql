WITH aki_index_admissions AS (
  -- Index admissions for female patients aged 52-62 with AKI on that admission,
  -- excluding in-hospital deaths and admissions missing discharge time.
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.hospital_expire_flag = 0
    AND a.hadm_id IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9  AND d.icd_code LIKE '584%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
        )
    )
),

index_with_readmit AS (
  -- For each index admission determine if there is any subsequent admission
  -- for the same subject within 30 days after discharge.
  SELECT
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM aki_index_admissions ia
)

SELECT
  STDDEV_SAMP(CASE WHEN readmitted_30d THEN 1.0 ELSE 0.0 END) AS sd_30day_readmission,
  COUNT(*) AS n_index_admissions,
  AVG(CASE WHEN readmitted_30d THEN 1.0 ELSE 0.0 END) AS readmission_rate
FROM index_with_readmit;