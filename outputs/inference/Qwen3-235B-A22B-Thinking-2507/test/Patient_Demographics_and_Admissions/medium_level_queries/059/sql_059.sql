WITH filtered AS (
  SELECT
    adm.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 75 AND 85
    AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
    AND (
      adm.discharge_location = 'HOME' 
      OR adm.discharge_location LIKE '%HOSPICE%' 
      OR adm.hospital_expire_flag = 1
    )
)
SELECT
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_los_ge7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75th_percentile
FROM filtered;