WITH antiplatelet_drugs AS (
  SELECT 'aspirin' AS drug_type, 'aspirin' AS drug_name_pattern
  UNION ALL
  SELECT 'p2y12_inhibitor', 'clopidogrel'
  UNION ALL
  SELECT 'p2y12_inhibitor', 'ticagrelor'
  UNION ALL
  SELECT 'p2y12_inhibitor', 'prasugrel'
),
latest_poe AS (
  SELECT
    poe_id,
    poe_seq,
    FIRST_VALUE(order_status) OVER (PARTITION BY poe_id, poe_seq ORDER BY ordertime DESC) AS latest_status
  FROM `physionet-data.mimiciv_3_1_hosp.poe`
  GROUP BY poe_id, poe_seq
),
prescriptions_with_drug_type AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    ad.drug_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN antiplatelet_drugs ad
    ON LOWER(p.drug) LIKE CONCAT('%', LOWER(ad.drug_name_pattern), '%')
  WHERE p.stoptime IS NOT NULL
),
admissions_with_patients AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    TIMESTAMP_DIFF(a.admittime, DATE_SUB(FROM_YEARS(p.anchor_year), INTERVAL p.anchor_age YEAR), YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, DATE_SUB(FROM_YEARS(p.anchor_year), INTERVAL p.anchor_age YEAR), YEAR) BETWEEN 64 AND 74
),
prescriptions_with_status AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug_type
  FROM prescriptions_with_drug_type p
  JOIN latest_poe lp
    ON p.poe_id = lp.poe_id AND p.poe_seq = lp.poe_seq
  WHERE lp.latest_status NOT IN ('cancelled', 'discontinued')
),
clipped_prescriptions AS (
  SELECT
    p.hadm_id,
    p.drug_type,
    GREATEST(p.starttime, a.admittime) AS clipped_start,
    LEAST(p.stoptime, a.dischtime) AS clipped_end
  FROM prescriptions_with_status p
  JOIN admissions_with_patients a
    ON p.hadm_id = a.hadm_id
  WHERE p.starttime < a.dischtime
    AND p.stoptime > a.admittime
),
admissions_with_both_drugs AS (
  SELECT
    hadm_id
  FROM clipped_prescriptions
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT drug_type) = 2
),
filtered_clipped_prescriptions AS (
  SELECT
    cp.hadm_id,
    cp.clipped_start,
    cp.clipped_end
  FROM clipped_prescriptions cp
  JOIN admissions_with_both_drugs abd
    ON cp.hadm_id = abd.hadm_id
),
intervals_for_merging AS (
  SELECT
    hadm_id,
    clipped_start AS start_time,
    clipped_end AS end_time,
    LAG(clipped_end) OVER (PARTITION BY hadm_id ORDER BY clipped_start) AS prev_end
  FROM filtered_clipped_prescriptions
),
groups AS (
  SELECT
    hadm_id,
    start_time,
    end_time,
    CASE
      WHEN prev_end IS NULL THEN 1
      WHEN start_time <= prev_end THEN 0
      ELSE 1
    END AS is_new_group
  FROM intervals_for_merging
),
grouped_intervals AS (
  SELECT
    hadm_id,
    start_time,
    end_time,
    SUM(is_new_group) OVER (PARTITION BY hadm_id ORDER BY start_time) AS group_id
  FROM groups
),
merged_intervals AS (
  SELECT
    hadm_id,
    MIN(start_time) AS merged_start,
    MAX(end_time) AS merged_end
  FROM grouped_intervals
  GROUP BY hadm_id, group_id
),
admission_durations AS (
  SELECT
    hadm_id,
    SUM(TIMESTAMP_DIFF(merged_end, merged_start, MILLISECOND) / 86400000.0) AS total_duration_days
  FROM merged_intervals
  GROUP BY hadm_id
)
SELECT
  APPROX_QUANTILES(total_duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM admission_durations;