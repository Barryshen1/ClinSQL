SELECT
  a.hospital_expire_flag AS discharge_status,
  COUNT(*) AS n_patients,
  ROUND(AVG(los), 2) AS mean_los_days,
  ROUND(STDDEV(los), 2) AS sd_los_days,
  ROUND(100 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_7
FROM (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND LOWER(adm.admission_location) LIKE '%ed%'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
) a
GROUP BY
  a.hospital_expire_flag
ORDER BY
  a.hospital_expire_flag DESC;