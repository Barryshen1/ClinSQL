WITH PatientAgeGroup AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN anchor_age BETWEEN 73 AND 83 THEN '73-83'
      ELSE 'Other'
    END AS age_group
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
DeviceCounts AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.age_group,
    COUNT(DISTINCT e.itemid) AS distinct_device_count
  FROM PatientAgeGroup AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON p.subject_id = e.subject_id AND p.hadm_id = e.hadm_id
  WHERE
    p.age_group = '73-83'
    AND e.medication LIKE '%mechanical circulatory support%'
  GROUP BY
    p.subject_id,
    p.hadm_id,
    p.age_group
)
SELECT
  MEDIAN(distinct_device_count) AS median_distinct_devices
FROM DeviceCounts;