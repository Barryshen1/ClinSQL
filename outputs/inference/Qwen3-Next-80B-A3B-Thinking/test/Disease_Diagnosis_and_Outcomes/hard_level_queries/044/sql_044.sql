WITH female_59_69_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    CASE 
      WHEN p.dod IS NOT NULL AND p.dod <= a.admittime + INTERVAL 30 DAY THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    a.dischtime - a.admittime AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

cardiac_arrest_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (d.icd_version = 9 AND d.icd_code = '427.5') 
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I46%')
),

sofa_scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.value AS sofa_score,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE c.itemid = 228251
),

sofa_scores_filtered AS (
  SELECT subject_id, hadm_id, sofa_score
  FROM sofa_scores
  WHERE rn = 1
),

cardiac_arrest_with_sofa AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.thirty_day_mortality,
    f.los,
    s.sofa_score
  FROM female_59_69_admissions f
  JOIN cardiac_arrest_patients c 
    ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id
  LEFT JOIN sofa_scores_filtered s 
    ON f.subject_id = s.subject_id AND f.hadm_id = s.hadm_id
),

quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY sofa_score) AS quartile
  FROM cardiac_arrest_with_sofa
),

cardio_complications AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    (d.icd_version = 9 AND d.icd_code BETWEEN '410' AND '414') 
    OR (d.icd_version = 9 AND d.icd_code = '428')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I20%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I22%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I23%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I24%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I25%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
),

neuro_complications AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '438')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I60%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I62%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I64%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'I67%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'G40%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'G41%')
),

cardio_status AS (
  SELECT 
    q.subject_id,
    q.hadm_id,
    CASE WHEN c.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_cardio_complication
  FROM quartiles q
  LEFT JOIN cardio_complications c 
    ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id
),

neuro_status AS (
  SELECT 
    q.subject_id,
    q.hadm_id,
    CASE WHEN n.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_neuro_complication
  FROM quartiles q
  LEFT JOIN neuro_complications n 
    ON q.subject_id = n.subject_id AND q.hadm_id = n.hadm_id
),

quartile_data AS (
  SELECT 
    q.quartile,
    q.thirty_day_mortality,
    c.has_cardio_complication,
    n.has_neuro_complication,
    q.los,
    CASE WHEN q.thirty_day_mortality = 0 THEN q.los ELSE NULL END AS survivor_los
  FROM quartiles q
  LEFT JOIN cardio_status c 
    ON q.subject_id = c.subject_id AND q.hadm_id = c.hadm_id
  LEFT JOIN neuro_status n 
    ON q.subject_id = n.subject_id AND q.hadm_id = n.hadm_id
),

quartile_metrics AS (
  SELECT 
    quartile,
    AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
    AVG(has_cardio_complication) AS cardio_complication_rate,
    AVG(has_neuro_complication) AS neuro_complication_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY survivor_los) AS median_survivor_los
  FROM quartile_data
  GROUP BY quartile
),

baseline_mortality AS (
  SELECT AVG(thirty_day_mortality) AS baseline_rate
  FROM female_59_69_admissions
)

SELECT 
  qm.quartile,
  qm.thirty_day_mortality_rate,
  qm.cardio_complication_rate,
  qm.neuro_complication_rate,
  qm.median_survivor_los,
  bm.baseline_rate
FROM quartile_metrics qm
CROSS JOIN baseline_mortality bm
ORDER BY qm.quartile;