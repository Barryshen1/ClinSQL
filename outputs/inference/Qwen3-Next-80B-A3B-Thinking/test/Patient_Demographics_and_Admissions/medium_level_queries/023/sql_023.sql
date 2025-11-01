WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location IN ('HOME', 'HOME HEALTH CARE', 'HOME WITH HOSPICE') THEN 'Home'
      WHEN a.discharge_location IN ('REHAB', 'SKILLED NURSING FACILITY', 'FACILITY', 'REHABILITATION', 'LONG TERM CARE', 'OTHER FACILITY') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 41 AND 51
    AND a.admission_location LIKE 'EMERGENCY%'
)
SELECT
  discharge_category,
  COUNTIF(los >= 7) / COUNT(*) AS proportion_los_ge7,
  (COUNTIF(los <= 10) / COUNT(*)) * 100 AS percentile_rank_10_day_los
FROM filtered_admissions
WHERE discharge_category IN ('Home', 'Facility', 'Death')
GROUP BY discharge_category;