WITH primary_aki AS (
  SELECT 
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
      OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
    )
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN primary_aki pa
    ON a.hadm_id = pa.hadm_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 52 AND 62
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los
FROM filtered_admissions;