WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- compute LOS in full days
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- classify discharge category
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN UPPER(a.discharge_location) LIKE 'HOME%' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND UPPER(a.admission_location) = 'EMERGENCY ROOM'
)
SELECT
  discharge_category,
  COUNT(*) AS total_patients,
  -- proportion with LOS >= 7
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS prop_los_ge_7,
  -- percentile‐rank of 10‐day LOS = proportion with LOS <= 10
  SAFE_DIVIDE(
    SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS pct_rank_10day_los
FROM
  cohort
GROUP BY
  discharge_category
ORDER BY
  discharge_category;