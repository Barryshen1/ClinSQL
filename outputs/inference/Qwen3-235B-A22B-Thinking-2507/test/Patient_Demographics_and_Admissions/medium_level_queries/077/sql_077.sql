SELECT
  hospital_expire_flag AS status,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  COUNTIF(los_days <= 5.0) * 100.0 / COUNT(*) AS percent_los_le_5
FROM (
  SELECT
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  WHERE
    pat.gender = 'M'
    AND adm.admission_location = 'EMERGENCY ROOM ADMIT'
    AND adm.dischtime IS NOT NULL
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 41 AND 51
)
GROUP BY status;