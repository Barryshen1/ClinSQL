SELECT
  discharge_category,
  COUNTIF(los >= 7) / COUNT(*) AS proportion_ge7,
  COUNTIF(los <= 7) / COUNT(*) AS percentile_rank_7
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'DEATH'
      WHEN discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'HOME'
      ELSE 'FACILITY'
    END AS discharge_category,
    DATE_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 75 AND 85
    AND (a.hospital_expire_flag = 1 OR a.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'REHAB', 'SNF', 'LONG TERM CARE', 'OTHER FACILITY'))
) AS subquery
GROUP BY discharge_category;