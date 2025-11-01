WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- approximate birth year then compute age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
)
SELECT
  COUNT(*) AS n_patients,
  -- 25th percentile of the binary in-hospital mortality flag (approximate)
  APPROX_QUANTILES(CAST(hospital_expire_flag AS INT64), 100)[OFFSET(25)] AS p25_inhospital_mortality,
  -- overall observed in-hospital mortality proportion for context
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate
FROM first_admissions
WHERE rn = 1
  AND gender = 'M'
  AND age_at_admit BETWEEN 73 AND 83;