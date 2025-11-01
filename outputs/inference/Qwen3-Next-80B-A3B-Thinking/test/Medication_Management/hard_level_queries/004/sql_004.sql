WITH cyp3a4_drugs AS (
  SELECT 'cyclosporine' AS drug_name UNION ALL
  SELECT 'tacrolimus' UNION ALL
  SELECT 'simvastatin' UNION ALL
  SELECT 'atorvastatin' UNION ALL
  SELECT 'lovastatin' UNION ALL
  SELECT 'midazolam' UNION ALL
  SELECT 'quinidine' UNION ALL
  SELECT 'ketoconazole' UNION ALL
  SELECT 'itraconazole' UNION ALL
  SELECT 'erythromycin' UNION ALL
  SELECT 'clarithromycin' UNION ALL
  SELECT 'rifampin' UNION ALL
  SELECT 'phenytoin' UNION ALL
  SELECT 'carbamazepine' UNION ALL
  SELECT 'phenobarbital' UNION ALL
  SELECT 'diltiazem' UNION ALL
  SELECT 'verapamil' UNION ALL
  SELECT 'griseofulvin' UNION ALL
  SELECT 'fluconazole' UNION ALL
  SELECT 'voriconazole' UNION ALL
  SELECT 'efavirenz' UNION ALL
  SELECT 'nevirapine' UNION ALL
  SELECT 'ritonavir' UNION ALL
  SELECT 'indinavir' UNION ALL
  SELECT 'saquinavir' UNION ALL
  SELECT 'nelfinavir' UNION ALL
  SELECT 'amprenavir' UNION ALL
  SELECT 'fosamprenavir' UNION ALL
  SELECT 'tipranavir' UNION ALL
  SELECT 'boceprevir' UNION ALL
  SELECT 'telaprevir' UNION ALL
  SELECT 'cobicistat' UNION ALL
  SELECT 'elvitegravir' UNION ALL
  SELECT 'dolutegravir' UNION ALL
  SELECT 'rilpivirine' UNION ALL
  SELECT 'etravirine' UNION ALL
  SELECT 'maraviroc' UNION ALL
  SELECT 'atazanavir' UNION ALL
  SELECT 'darunavir' UNION ALL
  SELECT 'fostemsavir' UNION ALL
  SELECT 'ibalizumab' UNION ALL
  SELECT 'enfuvirtide'
),

stroke_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.icd_code LIKE 'I63%'
),

complexity_score AS (
  SELECT 
    sp.subject_id, 
    sp.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM stroke_patients sp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON sp.subject_id = pr.subject_id AND sp.hadm_id = pr.hadm_id
  GROUP BY sp.subject_id, sp.hadm_id
),

has_cyp3a4 AS (
  SELECT 
    sp.subject_id, 
    sp.hadm_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      JOIN cyp3a4_drugs c 
        ON LOWER(pr.drug) LIKE '%' || c.drug_name || '%'
      WHERE pr.subject_id = sp.subject_id 
        AND pr.hadm_id = sp.hadm_id
    ) THEN 1 ELSE 0 END AS has_cyp3a4_interaction
  FROM stroke_patients sp
),

cohort AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    sp.admittime,
    sp.dischtime,
    sp.hospital_expire_flag,
    cs.complexity_score,
    hc.has_cyp3a4_interaction,
    DATETIME_DIFF(sp.dischtime, sp.admittime, DAY) AS los
  FROM stroke_patients sp
  LEFT JOIN complexity_score cs 
    ON sp.subject_id = cs.subject_id AND sp.hadm_id = cs.hadm_id
  LEFT JOIN has_cyp3a4 hc 
    ON sp.subject_id = hc.subject_id AND sp.hadm_id = hc.hadm_id
)

SELECT 
  has_cyp3a4_interaction,
  AVG(complexity_score) AS avg_complexity,
  PERCENTILE_CONT(complexity_score, 0.25) WITHIN GROUP (ORDER BY complexity_score) AS p25_complexity,
  PERCENTILE_CONT(complexity_score, 0.5) WITHIN GROUP (ORDER BY complexity_score) AS median_complexity,
  PERCENTILE_CONT(complexity_score, 0.75) WITHIN GROUP (ORDER BY complexity_score) AS p75_complexity,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort
GROUP BY has_cyp3a4_interaction

UNION ALL

SELECT 
  'Top Quartile' AS has_cyp3a4_interaction,
  NULL AS avg_complexity,
  NULL AS p25_complexity,
  NULL AS median_complexity,
  NULL AS p75_complexity,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM (
  SELECT 
    los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM cohort
) 
WHERE quartile = 4;