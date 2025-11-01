WITH status_epi_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND LOWER(ddi.long_title) LIKE '%status epilepticus%'
),
meds_24h AS (
  SELECT 
    sp.subject_id, 
    sp.hadm_id,
    pr.drug,
    CASE
      WHEN LOWER(pr.drug) LIKE '%amiodarone%' OR LOWER(pr.drug) LIKE '%haloperidol%' OR LOWER(pr.drug) LIKE '%methadone%' 
           OR LOWER(pr.drug) LIKE '%ciprofloxacin%' THEN 'QT_prolonging'
      WHEN LOWER(pr.drug) LIKE '%warfarin%' OR LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%dabigatran%' 
           OR LOWER(pr.drug) LIKE '%aspirin%' THEN 'Bleeding_risk'
      ELSE 'General'
    END AS med_category
  FROM status_epi_patients sp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON sp.subject_id = pr.subject_id AND sp.hadm_id = pr.hadm_id
  WHERE pr.starttime BETWEEN sp.admittime AND DATETIME_ADD(sp.admittime, INTERVAL 24 HOUR)
),
complexity AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS med_count,
    COUNT(DISTINCT CASE WHEN med_category = 'QT_prolonging' THEN drug END) AS qt_count,
    COUNT(DISTINCT CASE WHEN med_category = 'Bleeding_risk' THEN drug END) AS bleed_count
  FROM meds_24h
  GROUP BY subject_id, hadm_id
),
complexity_with_rank AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.med_count,
    c.qt_count,
    c.bleed_count,
    PERCENT_RANK() OVER (ORDER BY c.med_count) AS complexity_percentile
  FROM complexity c
),
top_quartile AS (
  SELECT 
    cq.subject_id,
    cq.hadm_id,
    cq.med_count,
    cq.qt_count,
    cq.bleed_count,
    cq.complexity_percentile,
    sp.admittime,
    sp.dischtime,
    DATETIME_DIFF(sp.dischtime, sp.admittime, DAY) AS los_days,
    sp.hospital_expire_flag,
    CASE 
      WHEN cq.qt_count > 0 THEN 'QT_prolonging'
      WHEN cq.bleed_count > 0 THEN 'Bleeding_risk'
      ELSE 'General'
    END AS primary_category
  FROM complexity_with_rank cq
  JOIN status_epi_patients sp
    ON cq.subject_id = sp.subject_id AND cq.hadm_id = sp.hadm_id
  WHERE cq.complexity_percentile >= 0.75
)
SELECT 
  primary_category,
  COUNT(*) AS n_admissions,
  AVG(los_days) AS avg_los_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
FROM top_quartile
GROUP BY primary_category
ORDER BY primary_category;