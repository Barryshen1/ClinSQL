WITH eligible_stays AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 38 AND 48
),
first_heart_rate AS (
  SELECT 
    es.stay_id,
    c.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY es.stay_id 
      ORDER BY c.charttime
    ) AS rn
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents c
    ON es.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items d
    ON c.itemid = d.itemid
  WHERE d.label = 'Heart Rate'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= es.intime
    AND c.charttime <= es.outtime
)
SELECT MIN(valuenum) AS min_first_heart_rate
FROM first_heart_rate
WHERE rn = 1;