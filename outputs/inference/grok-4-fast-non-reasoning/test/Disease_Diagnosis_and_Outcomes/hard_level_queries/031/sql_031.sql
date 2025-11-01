WITH cohort AS (
  -- Base cohort: female, age 85-95, asthma exacerbation principal diagnosis
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.long_title AS asthma_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
    AND EXTRACT(YEAR FROM a.admittime) >= p.anchor_year  -- Ensure age aligns with admission year
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95  -- Fixed: unquoted numerics for INT64 comparison
    AND LOWER(d.long_title) LIKE '%asthma%'
    AND diag.icd_version = '10'
    AND a.hospital_expire_flag IN (0, 1)
),

elixhauser_groups AS (
  -- Get all Elixhauser comorbidity flags per admission (using standard v2023 ICD-10 mappings)
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN d.long_title LIKE '%cardiac arrhythmias%' THEN 1 ELSE 0 END) AS arrhyth,
    MAX(CASE WHEN d.long_title LIKE '%peripheral vascular disease%' THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN d.long_title LIKE '%hypertension%complicate%' THEN 1 ELSE 0 END) AS htn_cx,
    MAX(CASE WHEN d.long_title LIKE '%pulmonary circulation%' THEN 1 ELSE 0 END) AS pulm_circ,
    MAX(CASE WHEN d.long_title LIKE '%paralysis%' THEN 1 ELSE 0 END) AS paralysis,
    MAX(CASE WHEN d.long_title LIKE '%other neurological%' THEN 1 ELSE 0 END) AS other_neuro,
    MAX(CASE WHEN d.long_title LIKE '%chronic pulmonary%' THEN 1 ELSE 0 END) AS chron_pulm,
    MAX(CASE WHEN d.long_title LIKE '%diabetes%complicate%' THEN 1 ELSE 0 END) AS dm_cx,
    MAX(CASE WHEN d.long_title LIKE '%hypothyroidism%' THEN 1 ELSE 0 END) AS hypo_t,
    MAX(CASE WHEN d.long_title LIKE '%renal failure%' THEN 1 ELSE 0 END) AS renal_fail,
    MAX(CASE WHEN d.long_title LIKE '%liver disease%' THEN 1 ELSE 0 END) AS liver,
    MAX(CASE WHEN d.long_title LIKE '%peptic ulcer%' THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN d.long_title LIKE '%AIDS%' OR d.long_title LIKE '%HIV%' THEN 1 ELSE 0 END) AS aids,
    MAX(CASE WHEN d.long_title LIKE '%lymphoma%' THEN 1 ELSE 0 END) AS lymphoma,
    MAX(CASE WHEN d.long_title LIKE '%metastatic cancer%' THEN 1 ELSE 0 END) AS metro_ca,
    MAX(CASE WHEN d.long_title LIKE '%tumor%without%' THEN 1 ELSE 0 END) AS solid_tumor,
    MAX(CASE WHEN d.long_title LIKE '%rheumatoid arthritis%' OR d.long_title LIKE '%collagen%' THEN 1 ELSE 0 END) AS rheum,
    MAX(CASE WHEN d.long_title LIKE '%coagulopathy%' THEN 1 ELSE 0 END) AS coag,
    MAX(CASE WHEN d.long_title LIKE '%obesity%' THEN 1 ELSE 0 END) AS obesity,
    MAX(CASE WHEN d.long_title LIKE '%weight loss%' THEN 1 ELSE 0 END) AS wt_loss,
    MAX(CASE WHEN d.long_title LIKE '%fluid%electrolyte%' THEN 1 ELSE 0 END) AS fe,
    MAX(CASE WHEN d.long_title LIKE '%blood loss anemia%' THEN 1 ELSE 0 END) AS blood_anem,
    MAX(CASE WHEN d.long_title LIKE '%deficiency anemias%' THEN 1 ELSE 0 END) AS def_anem,
    MAX(CASE WHEN d.long_title LIKE '%alcohol abuse%' THEN 1 ELSE 0 END) AS alcohol,
    MAX(CASE WHEN d.long_title LIKE '%drug abuse%' THEN 1 ELSE 0 END) AS drug,
    MAX(CASE WHEN d.long_title LIKE '%psychoses%' THEN 1 ELSE 0 END) AS psych,
    MAX(CASE WHEN d.long_title LIKE '%depression%' THEN 1 ELSE 0 END) AS depress
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_all
    ON c.hadm_id = diag_all.hadm_id AND diag_all.icd_version = '10'
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag_all.icd_code = d.icd_code AND diag_all.icd_version = d.icd_version
  GROUP BY 
    c.hadm_id
),

elixhauser_scores AS (
  -- Compute van Walraven weighted score per admission
  SELECT 
    hadm_id,
    (chf * 9 + arrhyth * 9 + pvd * 6 + htn_cx * 5 + pulm_circ * 5 + paralysis * 5 + 
     other_neuro * 5 + chron_pulm * 4 + dm_cx * 3 + hypo_t * 3 + renal_fail * 3 + 
     liver * 3 + pud * 3 + aids * 6 + lymphoma * 6 + metro_ca * 6 + solid_tumor * 4 + 
     rheum * 4 + coag * 4 + obesity * (-9) + wt_loss * (-5) + fe * 9 + 
     blood_anem * 6 + def_anem * 6 + alcohol * 4 + drug * 2 + psych * 2 + depress * 2) AS comorbidity_score
  FROM 
    elixhauser_groups
),

quartiles AS (
  -- Stratify by score quartiles
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY comorbidity_score) AS quartile
  FROM 
    elixhauser_scores
),

outcomes AS (
  -- Flag outcomes: mortality direct; complications as secondary diagnoses
  SELECT 
    q.hadm_id,
    q.quartile,
    q.comorbidity_score,
    c.hospital_expire_flag AS mortality,
    -- CV complications: secondary acute cardiac (e.g., MI, HF, arrest)
    MAX(CASE WHEN diag.seq_num > 1 AND (LOWER(diag.icd_code) LIKE 'i21%' OR LOWER(diag.icd_code) LIKE 'i46%' OR LOWER(diag.icd_code) LIKE 'i50%') THEN 1 ELSE 0 END) AS cv_comp,
    -- Neuro complications: secondary acute neuro (e.g., stroke, seizure, enceph)
    MAX(CASE WHEN diag.seq_num > 1 AND (LOWER(diag.icd_code) LIKE 'i63%' OR LOWER(diag.icd_code) LIKE 'g40%' OR LOWER(diag.icd_code) LIKE 'g45%' OR LOWER(diag.icd_code) LIKE 'r56%') THEN 1 ELSE 0 END) AS neuro_comp
  FROM 
    quartiles q
  INNER JOIN 
    cohort c
    ON q.hadm_id = c.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON q.hadm_id = diag.hadm_id AND diag.icd_version = '10'
  GROUP BY 
    q.hadm_id, q.quartile, q.comorbidity_score, c.hospital_expire_flag
)

-- Aggregate by quartile
SELECT 
  quartile,
  COUNT(*) AS total_patients,
  ROUND(SUM(mortality) * 100.0 / COUNT(*), 2) AS mortality_rate_percent,
  ROUND(COUNT(CASE WHEN cv_comp = 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS cv_complication_rate_percent,
  ROUND(COUNT(CASE WHEN neuro_comp = 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS neuro_complication_rate_percent,
  ROUND(AVG(comorbidity_score), 2) AS mean_comorbidity_score
FROM 
  outcomes
GROUP BY 
  quartile
ORDER BY 
  quartile;