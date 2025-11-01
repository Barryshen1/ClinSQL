SELECT
  death_category,
  COUNT(*) AS n,
  ROUND(AVG(los), 2) AS mean_los,
  ROUND(STDDEV(los), 2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS percent_less_than_10
FROM (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'Home death'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'FACILITY', 'HOSPICE') THEN 'Facility death'
      ELSE NULL
    END AS death_category,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND p.dod IS NOT NULL
) subquery
WHERE death_category IS NOT NULL
GROUP BY death_category;