WITH medicine_admissions AS (
  -- admissions that had any "medicine" service during the hospital stay
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.services`
  WHERE hadm_id IS NOT NULL
    AND curr_service IS NOT NULL
    -- match common variants like "med", "medicine", "medical" as a whole word (case-insensitive)
    AND REGEXP_CONTAINS(curr_service, r'(?i)\bmed(icine|ical)?\b')
),

cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    -- hospital length of stay in whole days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  JOIN medicine_admissions m
    USING (hadm_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

cohort_with_discharge AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%hospice%' THEN 'hospice'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'home'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)

SELECT
  discharge_group,
  COUNT(*) AS total_count,
  ROUND(100.0 * SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)), 2) AS pct_los_ge_7,
  ROUND(100.0 * SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(*)), 2) AS pct_los_ge_14,
  -- interpreted "7-day LOS percentile" as percent discharged at or before 7 days
  ROUND(100.0 * SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(*)), 2) AS pct_los_le_7
FROM cohort_with_discharge
WHERE discharge_group IN ('home', 'hospice', 'in-hospital death')
GROUP BY discharge_group
ORDER BY
  -- order results: home, hospice, in-hospital death
  CASE discharge_group
    WHEN 'home' THEN 1
    WHEN 'hospice' THEN 2
    WHEN 'in-hospital death' THEN 3
    ELSE 4
  END;