WITH first_stays AS (
  SELECT 
    stay_id, 
    subject_id, 
    hadm_id, 
    intime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),
eligible_stays AS (
  SELECT 
    fs.stay_id, 
    fs.subject_id, 
    fs.hadm_id, 
    fs.intime
  FROM first_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON fs.subject_id = p.subject_id
  WHERE fs.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
aki_flags AS (
  SELECT 
    subject_id, 
    hadm_id,
    MAX(CASE 
      WHEN icd_version = 9 AND icd_code LIKE '584%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'N17%' THEN 1
      ELSE 0 
    END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  GROUP BY subject_id, hadm_id
),
spo2_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE label = 'SpO2'
),
avg_spo2_per_stay AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce 
    ON ce.stay_id = es.stay_id
  INNER JOIN spo2_itemids si 
    ON ce.itemid = si.itemid
  WHERE ce.charttime >= es.intime
    AND ce.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
  HAVING COUNT(ce.valuenum) > 0
)
SELECT 
  CASE 
    WHEN asp.avg_spo2 < 90 THEN '<90'
    WHEN asp.avg_spo2 <= 92 THEN '90-92'
    WHEN asp.avg_spo2 <= 95 THEN '93-95'
    ELSE '>95'
  END AS spo2_category,
  COUNT(DISTINCT es.subject_id) AS patient_count,
  COUNT(DISTINCT CASE WHEN COALESCE(af.has_aki, 0) = 1 THEN es.subject_id END) * 1.0 
    / COUNT(DISTINCT es.subject_id) AS aki_rate
FROM avg_spo2_per_stay asp
INNER JOIN eligible_stays es 
  ON asp.stay_id = es.stay_id
LEFT JOIN aki_flags af 
  ON es.subject_id = af.subject_id 
  AND es.hadm_id = af.hadm_id
GROUP BY spo2_category
ORDER BY 
  CASE spo2_category 
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
  END;