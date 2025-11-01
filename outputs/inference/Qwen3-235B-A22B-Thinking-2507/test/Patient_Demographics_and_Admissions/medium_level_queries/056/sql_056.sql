WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    adm.hospital_expire_flag,
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    adm.admission_location = 'EMERGENCY ROOM ADMIT'
    AND pat.gender = 'M'
    AND adm.dischtime IS NOT NULL
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 67 AND 77
)
SELECT
  hospital_expire_flag AS discharge_status,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_ge7,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_los_ge14,
  SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS perc_rank_10
FROM
  filtered_admissions
GROUP BY
  hospital_expire_flag
ORDER BY
  hospital_expire_flag;