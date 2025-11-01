WITH eligible_patients AS (
  -- Female patients aged 48-58 with inpatient admissions and ICU stay
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, p.anchor_age, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),

stroke_patients AS (
  -- Hemorrhagic stroke (principal dx I61.* ICD-10)
  SELECT ep.*, TRUE AS is_stroke, COUNT(*) OVER (PARTITION BY ep.anchor_age) AS target_n
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ep.subject_id = d.subject_id AND ep.hadm_id = d.hadm_id
  WHERE d.icd_version = '10'
    AND d.icd_code LIKE 'I61%'
    AND d.seq_num = 1
),

control_patients AS (
  -- Age/gender-matched controls (no I61, sample size = stroke count per age)
  SELECT ep.*, FALSE AS is_stroke, sp.target_n
  FROM eligible_patients ep
  INNER JOIN stroke_patients sp
    ON ep.anchor_age = sp.anchor_age
  WHERE NOT EXISTS (
    SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.subject_id = ep.subject_id AND d.hadm_id = ep.hadm_id
      AND d.icd_version = '10' AND d.icd_code LIKE 'I61%'
  )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ep.anchor_age ORDER BY RAND()) <= sp.target_n
),

cohort AS (
  -- Union stroke and controls
  SELECT subject_id, hadm_id, admittime, anchor_age, stay_id, intime, is_stroke, target_n
  FROM stroke_patients
  UNION ALL
  SELECT subject_id, hadm_id, admittime, anchor_age, stay_id, intime, is_stroke, target_n
  FROM control_patients
),

medications_48h AS (
  -- All meds in first 48h of ICU (inputs + prescriptions)
  SELECT DISTINCT
    c.subject_id, c.hadm_id, c.stay_id, c.intime,
    COALESCE(ie.itemid, pr.pharmacy_id) AS med_id,  -- Unified ID
    COALESCE(ie.itemid, -1 * pr.pharmacy_id, 0) AS sort_id,  -- For distinct
    CASE 
      WHEN ie.itemid IS NOT NULL THEN di.label 
      ELSE pr.drug 
    END AS med_name,
    GREATEST(c.intime, COALESCE(ie.starttime, pr.starttime)) AS med_start,
    LEAST(c.intime + INTERVAL 48 HOUR, COALESCE(ie.endtime, pr.stoptime)) AS med_end
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON c.stay_id = ie.stay_id
    AND ie.starttime <= c.intime + INTERVAL 48 HOUR
    AND (ie.endtime IS NULL OR ie.endtime >= c.intime)
    AND ie.amount > 0
    AND LOWER(di.label) NOT LIKE '%nutrition%' AND LOWER(di.label) NOT LIKE '%fluid%'
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime <= c.intime + INTERVAL 48 HOUR
    AND (pr.stoptime IS NULL OR pr.stoptime >= c.intime)
    AND pr.dose_val_rx > 0
    AND LOWER(pr.drug) NOT LIKE '%nutrition%' AND LOWER(pr.drug) NOT LIKE '%fluid%'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE (ie.itemid IS NOT NULL OR pr.pharmacy_id IS NOT NULL)
    AND COALESCE(ie.itemid, pr.pharmacy_id) IS NOT NULL
),

serotonergic_meds AS (
  -- Flag and count serotonergic drugs (example itemids/drugs; expand as needed)
  SELECT 
    m.*,
    CASE 
      WHEN LOWER(m.med_name) LIKE '%sertraline%' OR LOWER(m.med_name) LIKE '%fluoxetine%' OR LOWER(m.med_name) LIKE '%venlafaxine%' 
        OR LOWER(m.med_name) LIKE '%fentanyl%' OR LOWER(m.med_name) LIKE '%ondansetron%' OR LOWER(m.med_name) LIKE '%linezolid%'
        OR m.sort_id IN (220895, 225002, 225168, 221605)  -- Example itemids
      THEN 1 ELSE 0 
    END AS is_serotonergic
  FROM medications_48h m
),

patient_meds AS (
  -- Aggregate per patient: complexity (distinct meds), serotonergic count
  SELECT 
    s.subject_id, s.hadm_id, s.is_stroke,
    COUNT(DISTINCT s.sort_id) AS complexity_score,
    SUM(s.is_serotonergic) AS serotonergic_count,
    CASE WHEN SUM(s.is_serotonergic) >= 2 THEN '>=2' ELSE '<2' END AS serotonergic_group
  FROM serotonergic_meds s
  WHERE s.med_start < s.med_end  -- Active in window
  GROUP BY s.subject_id, s.hadm_id, s.is_stroke
),

outcomes AS (
  -- Add outcomes
  SELECT 
    pm.*,
    a.dischtime,
    a.hospital_expire_flag,
    i.los AS icu_los,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag,
    NTILE(4) OVER (ORDER BY pm.complexity_score) AS complexity_quartile
  FROM patient_meds pm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pm.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pm.hadm_id = i.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pm.hadm_id ORDER BY i.intime) = 1
),

summary AS (
  -- Complexity distribution by stroke/control
  SELECT 
    is_stroke,
    complexity_score,
    COUNT(*) AS patient_count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY is_stroke) AS pct
  FROM outcomes
  GROUP BY is_stroke, complexity_score
),

serotonin_outcomes AS (
  -- Outcomes for >=2 vs <2 serotonergic, by stroke/control
  SELECT 
    is_stroke,
    serotonergic_group,
    COUNT(*) AS patient_count,
    AVG(hospital_los) AS avg_hospital_los,
    AVG(icu_los) AS avg_icu_los,
    AVG(mortality_flag) AS mortality_rate
  FROM outcomes
  GROUP BY is_stroke, serotonergic_group
),

quartile_outcomes AS (
  -- LOS/mortality for top complexity quartile (4), by stroke/control
  SELECT 
    is_stroke,
    complexity_quartile,
    COUNT(*) AS patient_count,
    AVG(hospital_los) AS avg_hospital_los,
    AVG(icu_los) AS avg_icu_los,
    AVG(mortality_flag) AS mortality_rate
  FROM outcomes
  WHERE complexity_quartile = 4
  GROUP BY is_stroke, complexity_quartile
)

-- Results: Distributions and outcomes
SELECT 'Complexity Distribution' AS metric_type, is_stroke, complexity_score AS category, patient_count, ROUND(pct, 2) AS percentage
FROM summary
UNION ALL
SELECT 'Serotonergic Outcomes' AS metric_type, is_stroke, serotonergic_group AS category, patient_count, ROUND(mortality_rate * 100, 2) AS mortality_rate_pct
FROM serotonin_outcomes
UNION ALL
SELECT 'Top Quartile Outcomes' AS metric_type, is_stroke, CAST(complexity_quartile AS STRING) AS category, patient_count, ROUND(mortality_rate * 100, 2) AS mortality_rate_pct
FROM quartile_outcomes
ORDER BY metric_type, is_stroke, category;