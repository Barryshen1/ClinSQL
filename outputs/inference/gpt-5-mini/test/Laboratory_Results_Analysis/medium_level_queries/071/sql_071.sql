WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
female_age_cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         p.anchor_age,
         p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 43 AND 53
),
first_troponin AS (
  -- earliest Troponin T within 24 hours of admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    le.charttime,
    COALESCE(le.valuenum, SAFE_CAST(le.value AS FLOAT64)) AS valuenum,
    le.ref_range_upper,
    le.storetime,
    le.itemid
  FROM female_age_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = c.hadm_id
   AND le.subject_id = c.subject_id
  JOIN troponin_items t
    ON le.itemid = t.itemid
  WHERE le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime, le.storetime) = 1
),
categorized AS (
  SELECT
    ft.*,
    TIMESTAMP_DIFF(ft.dischtime, ft.admittime, SECOND) / 86400.0 AS hosp_los_days,
    CASE
      WHEN valuenum IS NULL THEN 'Unknown'
      WHEN ref_range_upper IS NOT NULL THEN
        CASE
          WHEN valuenum <= ref_range_upper THEN 'Normal'
          WHEN valuenum > ref_range_upper AND valuenum < 2 * ref_range_upper THEN 'Borderline'
          ELSE 'Elevated'
        END
      ELSE
        CASE
          WHEN valuenum < 0.01 THEN 'Normal'
          WHEN valuenum >= 0.01 AND valuenum <= 0.03 THEN 'Borderline'
          ELSE 'Elevated'
        END
    END AS tn_category
  FROM first_troponin ft
)
SELECT
  tn_category AS troponin_category,
  admissions_count,
  ROUND(100.0 * admissions_count / SUM(admissions_count) OVER (), 2) AS pct_of_cohort,
  ROUND(avg_los, 2) AS avg_hospital_los_days
FROM (
  SELECT tn_category, COUNT(DISTINCT hadm_id) AS admissions_count, AVG(hosp_los_days) AS avg_los
  FROM categorized
  WHERE tn_category IN ('Normal', 'Borderline', 'Elevated')
  GROUP BY tn_category
) t
ORDER BY
  CASE tn_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;