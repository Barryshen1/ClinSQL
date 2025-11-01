WITH postop_complications AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.hadm_id = d.hadm_id
  WHERE d.icd_code LIKE 'T81%'
),

charlson_weights AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' THEN 1
      WHEN icd_code LIKE 'I50%' THEN 1
      WHEN icd_code IN ('I70.2', 'I73.1', 'I73.8', 'I73.9', 'I79.0', 'I79.8', 'I79.9') THEN 1
      WHEN icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I64%' THEN 1
      WHEN icd_code LIKE 'F01%' OR icd_code LIKE 'F02%' OR icd_code LIKE 'F03%' THEN 1
      WHEN icd_code LIKE 'J40%' OR icd_code LIKE 'J41%' OR icd_code LIKE 'J42%' OR icd_code LIKE 'J43%' OR icd_code LIKE 'J44%' OR icd_code LIKE 'J45%' OR icd_code LIKE 'J46%' THEN 1
      WHEN icd_code LIKE 'M05%' OR icd_code LIKE 'M06%' OR icd_code LIKE 'M31.0%' OR icd_code LIKE 'M31.1%' OR icd_code LIKE 'M31.2%' OR icd_code LIKE 'M31.3%' OR icd_code LIKE 'M31.4%' OR icd_code LIKE 'M31.5%' OR icd_code LIKE 'M31.6%' OR icd_code LIKE 'M31.7%' OR icd_code LIKE 'M31.8%' OR icd_code LIKE 'M31.9%' THEN 1
      WHEN icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%' THEN 1
      WHEN icd_code LIKE 'K70.0%' OR icd_code LIKE 'K70.1%' OR icd_code LIKE 'K70.2%' OR icd_code LIKE 'K70.3%' OR icd_code LIKE 'K70.9%' OR icd_code LIKE 'K71.0%' OR icd_code LIKE 'K71.1%' OR icd_code LIKE 'K71.2%' OR icd_code LIKE 'K71.3%' OR icd_code LIKE 'K71.4%' OR icd_code LIKE 'K71.5%' OR icd_code LIKE 'K71.6%' OR icd_code LIKE 'K71.7%' OR icd_code LIKE 'K71.8%' OR icd_code LIKE 'K71.9%' OR icd_code LIKE 'K72.0%' OR icd_code LIKE 'K72.1%' OR icd_code LIKE 'K72.2%' OR icd_code LIKE 'K72.3%' OR icd_code LIKE 'K72.4%' OR icd_code LIKE 'K72.5%' OR icd_code LIKE 'K72.6%' OR icd_code LIKE 'K72.7%' OR icd_code LIKE 'K72.8%' OR icd_code LIKE 'K72.9%' OR icd_code LIKE 'K73.0%' OR icd_code LIKE 'K73.1%' OR icd_code LIKE 'K73.2%' OR icd_code LIKE 'K73.3%' OR icd_code LIKE 'K73.4%' OR icd_code LIKE 'K73.5%' OR icd_code LIKE 'K73.6%' OR icd_code LIKE 'K73.7%' OR icd_code LIKE 'K73.8%' OR icd_code LIKE 'K73.9%' OR icd_code LIKE 'K74.0%' OR icd_code LIKE 'K74.1%' OR icd_code LIKE 'K74.2%' OR icd_code LIKE 'K74.3%' OR icd_code LIKE 'K74.4%' OR icd_code LIKE 'K74.5%' OR icd_code LIKE 'K74.6%' OR icd_code LIKE 'K74.7%' OR icd_code LIKE 'K74.8%' OR icd_code LIKE 'K74.9%' THEN 1
      WHEN icd_code LIKE 'E10.0%' OR icd_code LIKE 'E10.1%' OR icd_code LIKE 'E10.2%' OR icd_code LIKE 'E10.3%' OR icd_code LIKE 'E10.4%' OR icd_code LIKE 'E10.5%' OR icd_code LIKE 'E10.6%' OR icd_code LIKE 'E10.7%' OR icd_code LIKE 'E10.8%' OR icd_code LIKE 'E10.9%' OR icd_code LIKE 'E11.0%' OR icd_code LIKE 'E11.1%' OR icd_code LIKE 'E11.2%' OR icd_code LIKE 'E11.3%' OR icd_code LIKE 'E11.4%' OR icd_code LIKE 'E11.5%' OR icd_code LIKE 'E11.6%' OR icd_code LIKE 'E11.7%' OR icd_code LIKE 'E11.8%' OR icd_code LIKE 'E11.9%' OR icd_code LIKE 'E13.0%' OR icd_code LIKE 'E13.1%' OR icd_code LIKE 'E13.2%' OR icd_code LIKE 'E13.3%' OR icd_code LIKE 'E13.4%' OR icd_code LIKE 'E13.5%' OR icd_code LIKE 'E13.6%' OR icd_code LIKE 'E13.7%' OR icd_code LIKE 'E13.8%' OR icd_code LIKE 'E13.9%' OR icd_code LIKE 'E14.0%' OR icd_code LIKE 'E14.1%' OR icd_code LIKE 'E14.2%' OR icd_code LIKE 'E14.3%' OR icd_code LIKE 'E14.4%' OR icd_code LIKE 'E14.5%' OR icd_code LIKE 'E14.6%' OR icd_code LIKE 'E14.7%' OR icd_code LIKE 'E14.8%' OR icd_code LIKE 'E14.9%' THEN 1
      WHEN icd_code LIKE 'E10.2%' OR icd_code LIKE 'E10.3%' OR icd_code LIKE 'E10.4%' OR icd_code LIKE 'E10.5%' OR icd_code LIKE 'E10.6%' OR icd_code LIKE 'E11.2%' OR icd_code LIKE 'E11.3%' OR icd_code LIKE 'E11.4%' OR icd_code LIKE 'E11.5%' OR icd_code LIKE 'E11.6%' OR icd_code LIKE 'E13.2%' OR icd_code LIKE 'E13.3%' OR icd_code LIKE 'E13.4%' OR icd_code LIKE 'E13.5%' OR icd_code LIKE 'E13.6%' OR icd_code LIKE 'E14.2%' OR icd_code LIKE 'E14.3%' OR icd_code LIKE 'E14.4%' OR icd_code LIKE 'E14.5%' OR icd_code LIKE 'E14.6%' THEN 2
      WHEN icd_code LIKE 'G04.0%' OR icd_code LIKE 'G11.4%' OR icd_code LIKE 'G80.1%' OR icd_code LIKE 'G81.0%' OR icd_code LIKE 'G81.1%' OR icd_code LIKE 'G81.9%' OR icd_code LIKE 'G82.0%' OR icd_code LIKE 'G82.1%' OR icd_code LIKE 'G82.2%' OR icd_code LIKE 'G82.5%' OR icd_code LIKE 'G82.6%' THEN 2
      WHEN icd_code LIKE 'N18.0%' OR icd_code LIKE 'N18.1%' OR icd_code LIKE 'N18.2%' OR icd_code LIKE 'N18.3%' OR icd_code LIKE 'N18.4%' OR icd_code LIKE 'N18.5%' OR icd_code LIKE 'N18.6%' OR icd_code LIKE 'N19%' THEN 2
      WHEN icd_code LIKE 'C%' AND icd_code NOT LIKE 'C00%' AND icd_code NOT LIKE 'C01%' AND icd_code NOT LIKE 'C02%' AND icd_code NOT LIKE 'C03%' AND icd_code NOT LIKE 'C04%' AND icd_code NOT LIKE 'C05%' AND icd_code NOT LIKE 'C06%' AND icd_code NOT LIKE 'C07%' AND icd_code NOT LIKE 'C08%' AND icd_code NOT LIKE 'C09%' AND icd_code NOT LIKE 'C10%' AND icd_code NOT LIKE 'C11%' AND icd_code NOT LIKE 'C12%' AND icd_code NOT LIKE 'C13%' AND icd_code NOT LIKE 'C14%' AND icd_code NOT LIKE 'C15%' AND icd_code NOT LIKE 'C16%' AND icd_code NOT LIKE 'C17%' AND icd_code NOT LIKE 'C18%' AND icd_code NOT LIKE 'C19%' AND icd_code NOT LIKE 'C20%' AND icd_code NOT LIKE 'C21%' AND icd_code NOT LIKE 'C22%' AND icd_code NOT LIKE 'C23%' AND icd_code NOT LIKE 'C24%' AND icd_code NOT LIKE 'C25%' AND icd_code NOT LIKE 'C26%' AND icd_code NOT LIKE 'C27%' AND icd_code NOT LIKE 'C28%' AND icd_code NOT LIKE 'C29%' AND icd_code NOT LIKE 'C30%' AND icd_code NOT LIKE 'C31%' AND icd_code NOT LIKE 'C32%' AND icd_code NOT LIKE 'C33%' AND icd_code NOT LIKE 'C34%' AND icd_code NOT LIKE 'C35%' AND icd_code NOT LIKE 'C36%' AND icd_code NOT LIKE 'C37%' AND icd_code NOT LIKE 'C38%' AND icd_code NOT LIKE 'C39%' AND icd_code NOT LIKE 'C40%' AND icd_code NOT LIKE 'C41%' AND icd_code NOT LIKE 'C42%' AND icd_code NOT LIKE 'C43%' AND icd_code NOT LIKE 'C44%' AND icd_code NOT LIKE 'C45%' AND icd_code NOT LIKE 'C46%' AND icd_code NOT LIKE 'C47%' AND icd_code NOT LIKE 'C48%' AND icd_code NOT LIKE 'C49%' AND icd_code NOT LIKE 'C50%' AND icd_code NOT LIKE 'C51%' AND icd_code NOT LIKE 'C52%' AND icd_code NOT LIKE 'C53%' AND icd_code NOT LIKE 'C54%' AND icd_code NOT LIKE 'C55%' AND icd_code NOT LIKE 'C56%' AND icd_code NOT LIKE 'C57%' AND icd_code NOT LIKE 'C58%' AND icd_code NOT LIKE 'C59%' AND icd_code NOT LIKE 'C60%' AND icd_code NOT LIKE 'C61%' AND icd_code NOT LIKE 'C62%' AND icd_code NOT LIKE 'C63%' AND icd_code NOT LIKE 'C64%' AND icd_code NOT LIKE 'C65%' AND icd_code NOT LIKE 'C66%' AND icd_code NOT LIKE 'C67%' AND icd_code NOT LIKE 'C68%' AND icd_code NOT LIKE 'C69%' AND icd_code NOT LIKE 'C70%' AND icd_code NOT LIKE 'C71%' AND icd_code NOT LIKE 'C72%' AND icd_code NOT LIKE 'C73%' AND icd_code NOT LIKE 'C74%' AND icd_code NOT LIKE 'C75%' AND icd_code NOT LIKE 'C76%' AND icd_code NOT LIKE 'C77%' AND icd_code NOT LIKE 'C78%' AND icd_code NOT LIKE 'C79%' AND icd_code NOT LIKE 'C80%' THEN 2
      WHEN icd_code LIKE 'C91%' OR icd_code LIKE 'C92%' OR icd_code LIKE 'C93%' OR icd_code LIKE 'C94%' OR icd_code LIKE 'C95%' THEN 2
      WHEN icd_code LIKE 'C81%' OR icd_code LIKE 'C82%' OR icd_code LIKE 'C83%' OR icd_code LIKE 'C84%' OR icd_code LIKE 'C85%' OR icd_code LIKE 'C86%' OR icd_code LIKE 'C87%' OR icd_code LIKE 'C88%' OR icd_code LIKE 'C90%' OR icd_code LIKE 'C96%' THEN 2
      WHEN icd_code LIKE 'C77%' OR icd_code LIKE 'C78%' OR icd_code LIKE 'C79%' THEN 6
      WHEN icd_code LIKE 'B20%' OR icd_code LIKE 'B21%' OR icd_code LIKE 'B22%' OR icd_code LIKE 'B23%' OR icd_code LIKE 'B24%' THEN 6
      ELSE 0
    END AS weight
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

charlson_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(weight) AS charlson_score
  FROM charlson_weights
  GROUP BY subject_id, hadm_id
),

icu_status AS (
  SELECT
    a.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
)

SELECT
  icu_status,
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE '≥8'
  END AS los_category,
  CASE
    WHEN charlson_score <= 3 THEN '≤3'
    WHEN charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_category,
  COUNT(*) AS N,
  SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY time_to_death) AS median_time_to_death
FROM (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.deathtime,
    i.icu_status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    c.charlson_score,
    CASE WHEN a.hospital_expire_flag = 1 THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) END AS time_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN icu_status i ON a.hadm_id = i.hadm_id
  JOIN charlson_scores c ON a.hadm_id = c.hadm_id AND a.subject_id = c.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.hadm_id IN (SELECT hadm_id FROM postop_complications)
) subquery
GROUP BY icu_status, los_category, charlson_category;