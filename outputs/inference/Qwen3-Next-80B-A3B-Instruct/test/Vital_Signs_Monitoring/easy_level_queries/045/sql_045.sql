WITH respiratory_rate_items AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
first_respiratory_rate AS (
  SELECT 
    c.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  INNER JOIN respiratory_rate_items r ON c.itemid = r.itemid
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i ON c.stay_id = i.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 100  -- plausible range for respiratory rate
)
SELECT 
  STDDEV(valuenum) AS sd_first_respiratory_rate
FROM first_respiratory_rate
WHERE rn = 1;