WITH dvt_patients AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_version = 10 AND di.icd_code LIKE 'I82.4%'
),

admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.dod,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS admission_age
  FROM dvt_patients d
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON d.subject_id = p.subject_id
),

charlson_weights AS (
  SELECT 
    di.subject_id,
    di.hadm_id,
    CASE
      WHEN di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I25.2%' THEN 1
      WHEN di.icd_code LIKE 'I50%' THEN 1
      WHEN di.icd_code LIKE 'I70%' OR di.icd_code LIKE 'I73.1%' OR di.icd_code LIKE 'I73.8%' OR di.icd_code LIKE 'I73.9%' THEN 1
      WHEN di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%' THEN 1
      WHEN di.icd_code LIKE 'F01%' OR di.icd_code LIKE 'F02%' OR di.icd_code LIKE 'F03%' THEN 1
      WHEN di.icd_code LIKE 'J40%' OR di.icd_code LIKE 'J41%' OR di.icd_code LIKE 'J42%' OR di.icd_code LIKE 'J43%' OR di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J45%' OR di.icd_code LIKE 'J46%' THEN 1
      WHEN di.icd_code LIKE 'M05%' OR di.icd_code LIKE 'M06%' OR di.icd_code LIKE 'M31%' OR di.icd_code LIKE 'M32%' THEN 1
      WHEN di.icd_code LIKE 'K25%' OR di.icd_code LIKE 'K26%' OR di.icd_code LIKE 'K27%' OR di.icd_code LIKE 'K28%' THEN 1
      WHEN di.icd_code LIKE 'K70.0%' OR di.icd_code LIKE 'K70.1%' OR di.icd_code LIKE 'K70.2%' OR di.icd_code LIKE 'K70.3%' OR di.icd_code LIKE 'K71.3%' OR di.icd_code LIKE 'K71.4%' OR di.icd_code LIKE 'K71.5%' OR di.icd_code LIKE 'K73%' OR di.icd_code LIKE 'K74%' THEN 1
      WHEN di.icd_code LIKE 'E10.0%' OR di.icd_code LIKE 'E10.1%' OR di.icd_code LIKE 'E10.2%' OR di.icd_code LIKE 'E10.3%' OR di.icd_code LIKE 'E10.4%' OR di.icd_code LIKE 'E10.5%' OR di.icd_code LIKE 'E10.6%' OR di.icd_code LIKE 'E10.7%' OR di.icd_code LIKE 'E10.8%' OR di.icd_code LIKE 'E10.9%' THEN 1
      WHEN di.icd_code LIKE 'E11.0%' OR di.icd_code LIKE 'E11.1%' OR di.icd_code LIKE 'E11.2%' OR di.icd_code LIKE 'E11.3%' OR di.icd_code LIKE 'E11.4%' OR di.icd_code LIKE 'E11.5%' OR di.icd_code LIKE 'E11.6%' OR di.icd_code LIKE 'E11.7%' OR di.icd_code LIKE 'E11.8%' OR di.icd_code LIKE 'E11.9%' THEN 1
      WHEN di.icd_code LIKE 'E13.0%' OR di.icd_code LIKE 'E13.1%' OR di.icd_code LIKE 'E13.2%' OR di.icd_code LIKE 'E13.3%' OR di.icd_code LIKE 'E13.4%' OR di.icd_code LIKE 'E13.5%' OR di.icd_code LIKE 'E13.6%' OR di.icd_code LIKE 'E13.7%' OR di.icd_code LIKE 'E13.8%' OR di.icd_code LIKE 'E13.9%' THEN 1
      WHEN di.icd_code LIKE 'E14.0%' OR di.icd_code LIKE 'E14.1%' OR di.icd_code LIKE 'E14.2%' OR di.icd_code LIKE 'E14.3%' OR di.icd_code LIKE 'E14.4%' OR di.icd_code LIKE 'E14.5%' OR di.icd_code LIKE 'E14.6%' OR di.icd_code LIKE 'E14.7%' OR di.icd_code LIKE 'E14.8%' OR di.icd_code LIKE 'E14.9%' THEN 1
      WHEN di.icd_code LIKE 'E10.2%' OR di.icd_code LIKE 'E10.3%' OR di.icd_code LIKE 'E10.4%' OR di.icd_code LIKE 'E10.5%' OR di.icd_code LIKE 'E10.6%' OR di.icd_code LIKE 'E10.7%' OR di.icd_code LIKE 'E10.8%' OR di.icd_code LIKE 'E10.9%' THEN 2
      WHEN di.icd_code LIKE 'E11.2%' OR di.icd_code LIKE 'E11.3%' OR di.icd_code LIKE 'E11.4%' OR di.icd_code LIKE 'E11.5%' OR di.icd_code LIKE 'E11.6%' OR di.icd_code LIKE 'E11.7%' OR di.icd_code LIKE 'E11.8%' OR di.icd_code LIKE 'E11.9%' THEN 2
      WHEN di.icd_code LIKE 'E13.2%' OR di.icd_code LIKE 'E13.3%' OR di.icd_code LIKE 'E13.4%' OR di.icd_code LIKE 'E13.5%' OR di.icd_code LIKE 'E13.6%' OR di.icd_code LIKE 'E13.7%' OR di.icd_code LIKE 'E13.8%' OR di.icd_code LIKE 'E13.9%' THEN 2
      WHEN di.icd_code LIKE 'E14.2%' OR di.icd_code LIKE 'E14.3%' OR di.icd_code LIKE 'E14.4%' OR di.icd_code LIKE 'E14.5%' OR di.icd_code LIKE 'E14.6%' OR di.icd_code LIKE 'E14.7%' OR di.icd_code LIKE 'E14.8%' OR di.icd_code LIKE 'E14.9%' THEN 2
      WHEN di.icd_code LIKE 'G04.1%' OR di.icd_code LIKE 'G11.4%' OR di.icd_code LIKE 'G80%' OR di.icd_code LIKE 'G81%' OR di.icd_code LIKE 'G82%' THEN 2
      WHEN di.icd_code LIKE 'N18%' OR di.icd_code LIKE 'N19%' THEN 2
      WHEN di.icd_code LIKE 'C00%' OR di.icd_code LIKE 'C01%' OR di.icd_code LIKE 'C02%' OR di.icd_code LIKE 'C03%' OR di.icd_code LIKE 'C04%' OR di.icd_code LIKE 'C05%' OR di.icd_code LIKE 'C06%' OR di.icd_code LIKE 'C07%' OR di.icd_code LIKE 'C08%' OR di.icd_code LIKE 'C09%' OR di.icd_code LIKE 'C10%' OR di.icd_code LIKE 'C11%' OR di.icd_code LIKE 'C12%' OR di.icd_code LIKE 'C13%' OR di.icd_code LIKE 'C14%' OR di.icd_code LIKE 'C15%' OR di.icd_code LIKE 'C16%' OR di.icd_code LIKE 'C17%' OR di.icd_code LIKE 'C18%' OR di.icd_code LIKE 'C19%' OR di.icd_code LIKE 'C20%' OR di.icd_code LIKE 'C21%' OR di.icd_code LIKE 'C22%' OR di.icd_code LIKE 'C23%' OR di.icd_code LIKE 'C24%' OR di.icd_code LIKE 'C25%' OR di.icd_code LIKE 'C26%' OR di.icd_code LIKE 'C30%' OR di.icd_code LIKE 'C31%' OR di.icd_code LIKE 'C32%' OR di.icd_code LIKE 'C33%' OR di.icd_code LIKE 'C34%' OR di.icd_code LIKE 'C37%' OR di.icd_code LIKE 'C38%' OR di.icd_code LIKE 'C39%' OR di.icd_code LIKE 'C40%' OR di.icd_code LIKE 'C41%' OR di.icd_code LIKE 'C43%' OR di.icd_code LIKE 'C44%' OR di.icd_code LIKE 'C45%' OR di.icd_code LIKE 'C46%' OR di.icd_code LIKE 'C47%' OR di.icd_code LIKE 'C48%' OR di.icd_code LIKE 'C49%' OR di.icd_code LIKE 'C50%' OR di.icd_code LIKE 'C51%' OR di.icd_code LIKE 'C52%' OR di.icd_code LIKE 'C53%' OR di.icd_code LIKE 'C54%' OR di.icd_code LIKE 'C55%' OR di.icd_code LIKE 'C56%' OR di.icd_code LIKE 'C57%' OR di.icd_code LIKE 'C58%' OR di.icd_code LIKE 'C60%' OR di.icd_code LIKE 'C61%' OR di.icd_code LIKE 'C62%' OR di.icd_code LIKE 'C63%' OR di.icd_code LIKE 'C64%' OR di.icd_code LIKE 'C65%' OR di.icd_code LIKE 'C66%' OR di.icd_code LIKE 'C67%' OR di.icd_code LIKE 'C68%' OR di.icd_code LIKE 'C69%' OR di.icd_code LIKE 'C70%' OR di.icd_code LIKE 'C71%' OR di.icd_code LIKE 'C72%' OR di.icd_code LIKE 'C73%' OR di.icd_code LIKE 'C74%' OR di.icd_code LIKE 'C75%' OR di.icd_code LIKE 'C76%' OR di.icd_code LIKE 'C81%' OR di.icd_code LIKE 'C82%' OR di.icd_code LIKE 'C83%' OR di.icd_code LIKE 'C84%' OR di.icd_code LIKE 'C85%' OR di.icd_code LIKE 'C86%' OR di.icd_code LIKE 'C87%' OR di.icd_code LIKE 'C88%' OR di.icd_code LIKE 'C90%' OR di.icd_code LIKE 'C91%' OR di.icd_code LIKE 'C92%' OR di.icd_code LIKE 'C93%' OR di.icd_code LIKE 'C94%' OR di.icd_code LIKE 'C95%' OR di.icd_code LIKE 'C96%' OR di.icd_code LIKE 'C97%' THEN 2
      WHEN di.icd_code LIKE 'C77%' OR di.icd_code LIKE 'C78%' OR di.icd_code LIKE 'C79%' OR di.icd_code LIKE 'C80%' THEN 6
      WHEN di.icd_code LIKE 'B20%' OR di.icd_code LIKE 'B21%' OR di.icd_code LIKE 'B22%' OR di.icd_code LIKE 'B23%' OR di.icd_code LIKE 'B24%' THEN 6
      ELSE 0
    END AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.icd_version = 10
),

charlson_scores AS (
  SELECT 
    subject_id,
    hadm_id,
    SUM(weight) AS charlson_score
  FROM charlson_weights
  GROUP BY subject_id, hadm_id
),

filtered_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    c.charlson_score,
    CASE 
      WHEN a.dod IS NOT NULL AND a.dod <= a.admittime + INTERVAL 90 DAY THEN 1 
      ELSE 0 
    END AS mortality_90d,
    CASE 
      WHEN a.dischtime IS NOT NULL THEN DATE_DIFF(a.dischtime, a.admittime, DAY) 
      ELSE NULL 
    END AS los
  FROM admissions_with_age a
  LEFT JOIN charlson_scores c 
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  WHERE a.gender = 'M'
    AND a.admission_age BETWEEN 71 AND 81
    AND c.charlson_score >= 3
)

SELECT 
  PERCENTILE_CONT(charlson_score, 0.5) AS median_risk_score,
  PERCENTILE_CONT(charlson_score, 0.25) AS q1,
  PERCENTILE_CONT(charlson_score, 0.75) AS q3,
  (PERCENTILE_CONT(charlson_score, 0.75) - PERCENTILE_CONT(charlson_score, 0.25)) AS iqr,
  AVG(mortality_90d) AS ninety_day_mortality_rate,
  AVG(CASE WHEN mortality_90d = 0 THEN los ELSE NULL END) AS survivor_los_days
FROM filtered_patients;