SELECT
  hospital_expire_flag,
  COUNTIF(los_days >= 7) / COUNT(*) AS prop_7,
  COUNTIF(los_days >= 14) / COUNT(*) AS prop_14,
  COUNTIF(los_days <= 10) / COUNT(*) AS percentile_10
FROM (
  SELECT
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_location LIKE 'EMERGENCY%'
) subquery
GROUP BY hospital_expire_flag;