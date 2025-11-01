WITH filtered_patients AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year, 
    i.stay_id,
    i.intime,
    -- Calculate age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
),
age_filtered_stays AS (
  SELECT *
  FROM filtered_patients
  WHERE age_at_admission BETWEEN 77 AND 87
),
gcs_data AS (
  SELECT 
    a.stay_id,
    c.charttime,
    c.valuenum AS gcs_total
  FROM age_filtered_stays a
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON a.stay_id = c.stay_id
  WHERE c.itemid = 229  -- GCS Total
    AND c.valuenum IS NOT NULL
),
ranked_gcs AS (
  SELECT 
    stay_id,
    gcs_total,
    ROW_NUMBER() OVER (
      PARTITION BY stay_id 
      ORDER BY charttime
    ) AS rn  -- Rank GCS records per stay by time
  FROM gcs_data
)
SELECT 
  AVG(gcs_total) AS avg_first_gcs
FROM ranked_gcs
WHERE rn = 1;  -- Keep only the first GCS per stay;