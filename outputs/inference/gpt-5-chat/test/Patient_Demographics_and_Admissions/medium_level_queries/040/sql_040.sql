WITH surgical_inpatients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id,
    pat.gender, pat.anchor_age,
    adm.admittime, adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` AS srv
    ON adm.hadm_id = srv.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
    AND srv.curr_service IS NOT NULL
    AND REGEXP_CONTAINS(UPPER(srv.curr_service), r'SURG')  -- surgical services
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
),
los_calc AS (
  SELECT *,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'HOME') THEN 'Home'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'SNF')
        OR REGEXP_CONTAINS(UPPER(discharge_location), r'REHAB')
        OR REGEXP_CONTAINS(UPPER(discharge_location), r'LTACH')
        OR REGEXP_CONTAINS(UPPER(discharge_location), r'SKILLED NURSING')
        THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM surgical_inpatients
),
stats AS (
  SELECT discharge_category,
    COUNT(*) AS total_admissions,
    COUNTIF(los_days >= 7) AS los_ge_7_count,
    COUNTIF(los_days >= 14) AS los_ge_14_count
  FROM los_calc
  GROUP BY discharge_category
)
SELECT discharge_category,
  total_admissions,
  los_ge_7_count,
  ROUND(los_ge_7_count / total_admissions, 4) AS proportion_ge_7,
  los_ge_14_count,
  ROUND(los_ge_14_count / total_admissions, 4) AS proportion_ge_14
FROM stats
WHERE discharge_category IN ('Home', 'Facility', 'Death')
ORDER BY discharge_category;