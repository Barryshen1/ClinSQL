WITH eligible_females AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 48 AND 58
),
ischemic_stroke_admissions AS (
  SELECT iso.subject_id, iso.hadm_id, iso.admittime, iso.dischtime, iso.hospital_expire_flag
  FROM eligible_females iso
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON iso.subject_id = di.subject_id AND iso.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE dic.long_title LIKE '%ischemic stroke%'
     OR di.icd_code LIKE 'I63%'
),
nti_drugs AS (
  SELECT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%warfarin%'
     OR LOWER(drug) LIKE '%digoxin%'
     OR LOWER(drug) LIKE '%phenytoin%'
     OR LOWER(drug) LIKE '%theophylline%'
     OR LOWER(drug) LIKE '%tacrolimus%'
     OR LOWER(drug) LIKE '%cyclosporine%'
     OR LOWER(drug) LIKE '%lithium%'
  GROUP BY hadm_id, subject_id
),
cyto_inhibitors AS (
  SELECT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%ketoconazole%'
     OR LOWER(drug) LIKE '%itraconazole%'
     OR LOWER(drug) LIKE '%fluconazole%'
     OR LOWER(drug) LIKE '%voriconazole%'
     OR LOWER(drug) LIKE '%posaconazole%'
     OR LOWER(drug) LIKE '%erythromycin%'
     OR LOWER(drug) LIKE '%clarithromycin%'
     OR LOWER(drug) LIKE '%ritonavir%'
     OR LOWER(drug) LIKE '%cobicistat%'
  GROUP BY hadm_id, subject_id
),
interaction_pairs AS (
  SELECT nti.subject_id, nti.hadm_id
  FROM nti_drugs nti
  JOIN cyto_inhibitors cyto
    ON nti.subject_id = cyto.subject_id
   AND nti.hadm_id = cyto.hadm_id
),
stroke_admissions AS (
  SELECT iso.subject_id,
         iso.hadm_id,
         iso.admittime,
         iso.dischtime,
         iso.hospital_expire_flag,
         COUNT(DISTINCT CASE
           WHEN di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%' OR di.icd_code LIKE 'I65%' OR di.icd_code LIKE 'I66%' OR di.icd_code LIKE 'I67%' OR di.icd_code LIKE 'I68%' OR di.icd_code LIKE 'I69%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'I10%' OR di.icd_code LIKE 'I11%' OR di.icd_code LIKE 'I12%' OR di.icd_code LIKE 'I13%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E12%' OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'N18%' OR di.icd_code LIKE 'N19%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'K70%' OR di.icd_code LIKE 'K71%' OR di.icd_code LIKE 'K72%' OR di.icd_code LIKE 'K73%' OR di.icd_code LIKE 'K74%' OR di.icd_code LIKE 'K75%' OR di.icd_code LIKE 'K76%' OR di.icd_code LIKE 'K77%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'C%' 
           THEN di.icd_code
           WHEN di.icd_code LIKE 'J40%' OR di.icd_code LIKE 'J41%' OR di.icd_code LIKE 'J42%' OR di.icd_code LIKE 'J44%'
           THEN di.icd_code
           WHEN di.icd_code LIKE 'M35%' OR di.icd_code LIKE 'D64%' OR di.icd_code LIKE 'D45%' OR di.icd_code LIKE 'B20%'
           THEN di.icd_code
           ELSE NULL
         END) AS complexity_score
  FROM ischemic_stroke_admissions iso
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON iso.subject_id = di.subject_id AND iso.hadm_id = di.hadm_id
  GROUP BY iso.subject_id, iso.hadm_id, iso.admittime, iso.dischtime, iso.hospital_expire_flag
),
stroke_with_interaction AS (
  SELECT sw.*,
         CASE WHEN ip.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_interaction
  FROM stroke_admissions sw
  LEFT JOIN interaction_pairs ip
    ON sw.subject_id = ip.subject_id
   AND sw.hadm_id = ip.hadm_id
),
stroke_data AS (
  SELECT swi.subject_id,
         swi.hadm_id,
         swi.admittime,
         swi.dischtime,
         swi.hospital_expire_flag,
         swi.complexity_score,
         (TIMESTAMP_DIFF(swi.dischtime, swi.admittime, SECOND) / 86400.0) AS los_days,
         CASE WHEN swi.hospital_expire_flag = 'Y' THEN 1 ELSE 0 END AS mortality,
         swi.has_interaction
  FROM stroke_with_interaction swi
),
stroke_grouped AS (
  SELECT
    CASE WHEN has_interaction = 1 THEN 'NTI_with_inhibition' ELSE 'NTI_without_inhibition' END AS group_label,
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    complexity_score,
    los_days,
    mortality
  FROM stroke_data
),
stroke_with_quart AS (
  SELECT sg.*,
         NTILE(4) OVER (ORDER BY complexity_score DESC) AS quartile
  FROM stroke_grouped sg
),
stroke_medians AS (
  SELECT group_label,
         MAX(median_complexity_score) AS median_complexity_score
  FROM (
    SELECT group_label,
           PERCENTILE_CONT(0.5) OVER (PARTITION BY group_label ORDER BY complexity_score) AS median_complexity_score
    FROM stroke_with_quart
  )
  GROUP BY group_label
)

SELECT
  wq.group_label,
  COUNT(*) AS n_patients,
  AVG(wq.complexity_score) AS avg_complexity_score,
  sm.median_complexity_score AS median_complexity_score,
  AVG(wq.los_days) AS avg_los_days,
  AVG(wq.mortality) AS inhospital_mortality_rate,
  AVG(CASE WHEN wq.quartile = 1 THEN wq.los_days END) AS top_quart_los_days,
  AVG(CASE WHEN wq.quartile = 1 THEN wq.mortality END) AS top_quart_mortality
FROM stroke_with_quart wq
JOIN stroke_medians sm
  ON CAST(wq.group_label AS STRING) = CAST(sm.group_label AS STRING)
GROUP BY wq.group_label, sm.median_complexity_score
ORDER BY wq.group_label;