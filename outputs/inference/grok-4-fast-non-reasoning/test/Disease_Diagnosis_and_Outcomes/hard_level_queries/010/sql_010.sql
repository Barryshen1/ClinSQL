WITH cohort AS (
  -- Base cohort: males 39-49 with admissions
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    -- DKA flag: primary diagnosis
    CASE WHEN di.icd_code LIKE '250.1%' OR di.icd_code LIKE 'E[0-3][0-9].1' THEN 1 ELSE 0 END AS is_dka
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.subject_id = di.subject_id 
    AND a.hadm_id = di.hadm_id 
    AND di.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND a.hadm_id IS NOT NULL  -- Ensure inpatient
),

complications AS (
  -- Cardiovascular and neurologic complications (single query per admission)
  SELECT 
    c.subject_id,
    c.hadm_id,
    MAX(CASE WHEN dc.icd_code IN (
      '41000', '41001', '41010', '41011', '41020', '41021', '41030', '41031', '41040', '41041', '41050', '41051', '41060', '41061', '41070', '41071', '41080', '41081', '41090', '41091',
      '42731', '4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842',
      'I2101', 'I211', 'I212', 'I213', 'I214', 'I219', 'I48', 'I500', 'I5010', 'I5011', 'I509'
    ) THEN 1 ELSE 0 END) AS has_cardio_comp,
    MAX(CASE WHEN dc.icd_code IN (
      '3481', '430', '431', '4320', '4321', '4329', '43310', '43311', '43320', '43321', '43400', '43401', '43410', '43411', '436',
      'G931', 'I6300', 'I6311', 'I632', 'I633', 'I634', 'I635', 'I636', 'I637', 'I638', 'I639'
    ) THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dc 
    ON c.subject_id = dc.subject_id AND c.hadm_id = dc.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

enriched_cohort AS (
  SELECT 
    co.*,
    COALESCE(dc.drg_mortality, 0) AS drg_mortality,  -- Proxy risk score; default low
    -- 30-day death
    CASE 
      WHEN co.deathtime IS NOT NULL AND TIMESTAMP(co.deathtime) <= TIMESTAMP_ADD(TIMESTAMP(co.admittime), INTERVAL 30 DAY) THEN 1
      WHEN co.dod IS NOT NULL AND DATE(co.dod) <= DATE_ADD(DATE(co.admittime), INTERVAL 30 DAY) THEN 1
      ELSE 0 
    END AS death_30d,
    -- LOS for survivors (days)
    CASE 
      WHEN co.hospital_expire_flag = 0 AND co.dod IS NULL THEN DATE_DIFF(co.dischtime, co.admittime, DAY)
      ELSE NULL 
    END AS los_days,
    -- Complications
    comp.has_cardio_comp,
    comp.has_neuro_comp,
    -- Risk percentile (computed over full cohort for profile ranking)
    PERCENT_RANK() OVER (ORDER BY COALESCE(dc.drg_mortality, 0)) * 100 AS risk_percentile
  FROM cohort co
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc 
    ON co.subject_id = dc.subject_id AND co.hadm_id = dc.hadm_id AND dc.drg_type = 'MS-DRG'
  LEFT JOIN complications comp 
    ON co.subject_id = comp.subject_id AND co.hadm_id = comp.hadm_id
)

-- Aggregations: DKA vs All
SELECT 
  is_dka,
  COUNT(DISTINCT subject_id) AS n_patients,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  AVG(drg_mortality) AS mean_risk_score,
  AVG(death_30d) AS mortality_30d_rate,
  AVG(CASE WHEN has_cardio_comp = 1 THEN 1.0 ELSE 0 END) AS cardio_comp_rate,
  AVG(CASE WHEN has_neuro_comp = 1 THEN 1.0 ELSE 0 END) AS neuro_comp_rate,
  AVG(CASE WHEN los_days IS NOT NULL AND los_days > 0 THEN los_days ELSE NULL END) AS mean_los_survivors,
  -- Risk percentile for profile (avg across cohort; higher for DKA subgroup)
  AVG(risk_percentile) AS avg_risk_percentile
FROM enriched_cohort
GROUP BY is_dka
ORDER BY is_dka;