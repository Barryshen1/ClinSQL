SELECT
  discharge_cat,
  COUNT(*)                             AS total_patients,
  ROUND(  COUNTIF(los_days >= 7)   / COUNT(*) , 4) AS prop_los_ge_7,
  ROUND(  COUNTIF(los_days >= 14)  / COUNT(*) , 4) AS prop_los_ge_14,
  ROUND(  COUNTIF(los_days <= 7)   / COUNT(*) , 4) AS prop_disch_by_7
FROM (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1                                   THEN 'in-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%'                  THEN 'hospice'
      WHEN UPPER(a.discharge_location) LIKE '%HOME%'                     THEN 'home'
      ELSE 'other'
    END AS discharge_cat
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    -- Restrict to medicine service in this hospital admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.subject_id = a.subject_id
        AND s.hadm_id = a.hadm_id
        AND UPPER(s.curr_service) = 'MEDICINE'
    )
)
WHERE
  discharge_cat IN ('home', 'hospice', 'in-hospital death')
GROUP BY
  discharge_cat
ORDER BY
  discharge_cat;