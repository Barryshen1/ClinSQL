WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
)
SELECT
  APPROX_QUANTILES(hospital_expire_flag, 100)[OFFSET(25)] AS mortality_25th_percentile
FROM
  first_admissions
WHERE
  rn = 1
  AND gender = 'M'
  AND age_at_admission BETWEEN 73 AND 83;