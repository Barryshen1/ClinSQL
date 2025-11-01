WITH medicine_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    -- LOS in fractional days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  -- Male, age 74-84
  WHERE
    LOWER(p.gender) = 'm'
    AND p.anchor_age BETWEEN 74 AND 84
    -- require valid times
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- restrict to admissions where any service during the admission is medicine
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.services` s
      WHERE s.hadm_id = a.hadm_id
        AND LOWER(COALESCE(s.curr_service, '')) LIKE '%med%'
    )
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%hospice%' THEN 'Hospice'
      WHEN LOWER(COALESCE(discharge_location, '')) LIKE '%home%' THEN 'Home'
      ELSE NULL
    END AS discharge_category
  FROM medicine_admissions
)
SELECT
  discharge_category AS discharge_status,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  -- approximate median (50th percentile)
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(SAFE_DIVIDE(SUM(CASE WHEN los_days <= 5 THEN 1 ELSE 0 END), COUNT(*)), 4) AS proportion_los_le_5
FROM categorized
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY
  -- order rows: Home, Hospice, In-hospital death (optional)
  CASE discharge_category
    WHEN 'Home' THEN 1
    WHEN 'Hospice' THEN 2
    WHEN 'In-hospital death' THEN 3
    ELSE 4
  END;