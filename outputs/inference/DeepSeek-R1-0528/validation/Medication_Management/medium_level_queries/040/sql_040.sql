WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 36 AND 46
    AND adm.dischtime > adm.admittime
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 12
    AND adm.hadm_id IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%') OR 
        (icd_version = 10 AND icd_code LIKE 'E1%')
    )
    AND adm.hadm_id IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') OR 
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

time_windows AS (
  SELECT 
    hadm_id,
    admittime AS first48_start,
    DATETIME_ADD(admittime, INTERVAL 48 HOUR) AS first48_end,
    DATETIME_SUB(dischtime, INTERVAL 12 HOUR) AS last12_start,
    dischtime AS last12_end
  FROM cohort
),

drug_exposure AS (
  SELECT 
    tw.hadm_id,
    -- Antidiabetic in first 48h
    MAX(CASE WHEN 
              (LOWER(p.drug) LIKE '%insulin%' 
               OR LOWER(p.drug) LIKE '%metformin%'
               OR LOWER(p.drug) LIKE '%glipizide%'
               OR LOWER(p.drug) LIKE '%glyburide%'
               OR LOWER(p.drug) LIKE '%pioglitazone%'
               OR LOWER(p.drug) LIKE '%sitagliptin%'
               OR LOWER(p.drug) LIKE '%exenatide%'
               OR LOWER(p.drug) LIKE '%dapagliflozin%'
               OR LOWER(p.drug) LIKE '%canagliflozin%'
               OR LOWER(p.drug) LIKE '%empagliflozin%'
               OR LOWER(p.drug) LIKE '%acarbose%')
              AND p.starttime <= tw.first48_end 
              AND COALESCE(p.stoptime, tw.last12_end) >= tw.first48_start 
             THEN 1 ELSE 0 END) AS antidiabetic_first48,
    -- Antidiabetic in last 12h
    MAX(CASE WHEN 
              (LOWER(p.drug) LIKE '%insulin%' 
               OR LOWER(p.drug) LIKE '%metformin%'
               OR LOWER(p.drug) LIKE '%glipizide%'
               OR LOWER(p.drug) LIKE '%glyburide%'
               OR LOWER(p.drug) LIKE '%pioglitazone%'
               OR LOWER(p.drug) LIKE '%sitagliptin%'
               OR LOWER(p.drug) LIKE '%exenatide%'
               OR LOWER(p.drug) LIKE '%dapagliflozin%'
               OR LOWER(p.drug) LIKE '%canagliflozin%'
               OR LOWER(p.drug) LIKE '%empagliflozin%'
               OR LOWER(p.drug) LIKE '%acarbose%')
              AND p.starttime <= tw.last12_end 
              AND COALESCE(p.stoptime, tw.last12_end) >= tw.last12_start 
             THEN 1 ELSE 0 END) AS antidiabetic_last12,
    -- Cardiac in first 48h
    MAX(CASE WHEN 
              (LOWER(p.drug) LIKE '%beta blocker%'
               OR LOWER(p.drug) LIKE '%ace inhibitor%'
               OR LOWER(p.drug) LIKE '%arb%' 
               OR LOWER(p.drug) LIKE '%diuretic%'
               OR LOWER(p.drug) LIKE '%furosemide%'
               OR LOWER(p.drug) LIKE '%spironolactone%'
               OR LOWER(p.drug) LIKE '%digoxin%'
               OR LOWER(p.drug) LIKE '%statin%'
               OR LOWER(p.drug) LIKE '%carvedilol%'
               OR LOWER(p.drug) LIKE '%metoprolol%'
               OR LOWER(p.drug) LIKE '%lisinopril%'
               OR LOWER(p.drug) LIKE '%amlodipine%'
               OR LOWER(p.drug) LIKE '%nitroglycerin%'
               OR LOWER(p.drug) LIKE '%clopidogrel%'
               OR LOWER(p.drug) LIKE '%warfarin%'
               OR LOWER(p.drug) LIKE '%heparin%')
              AND p.starttime <= tw.first48_end 
              AND COALESCE(p.stoptime, tw.last12_end) >= tw.first48_start 
             THEN 1 ELSE 0 END) AS cardiac_first48,
    -- Cardiac in last 12h
    MAX(CASE WHEN 
              (LOWER(p.drug) LIKE '%beta blocker%'
               OR LOWER(p.drug) LIKE '%ace inhibitor%'
               OR LOWER(p.drug) LIKE '%arb%' 
               OR LOWER(p.drug) LIKE '%diuretic%'
               OR LOWER(p.drug) LIKE '%furosemide%'
               OR LOWER(p.drug) LIKE '%spironolactone%'
               OR LOWER(p.drug) LIKE '%digoxin%'
               OR LOWER(p.drug) LIKE '%statin%'
               OR LOWER(p.drug) LIKE '%carvedilol%'
               OR LOWER(p.drug) LIKE '%metoprolol%'
               OR LOWER(p.drug) LIKE '%lisinopril%'
               OR LOWER(p.drug) LIKE '%amlodipine%'
               OR LOWER(p.drug) LIKE '%nitroglycerin%'
               OR LOWER(p.drug) LIKE '%clopidogrel%'
               OR LOWER(p.drug) LIKE '%warfarin%'
               OR LOWER(p.drug) LIKE '%heparin%')
              AND p.starttime <= tw.last12_end 
              AND COALESCE(p.stoptime, tw.last12_end) >= tw.last12_start 
             THEN 1 ELSE 0 END) AS cardiac_last12
  FROM time_windows tw
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON tw.hadm_id = p.hadm_id
  GROUP BY tw.hadm_id
)

SELECT 
  ROUND(100 * AVG(antidiabetic_first48), 2) AS antidiabetic_first48_pct,
  ROUND(100 * AVG(antidiabetic_last12), 2) AS antidiabetic_last12_pct,
  ROUND(100 * AVG(antidiabetic_first48) - 100 * AVG(antidiabetic_last12), 2) AS antidiabetic_diff_pp,
  ROUND(100 * AVG(cardiac_first48), 2) AS cardiac_first48_pct,
  ROUND(100 * AVG(cardiac_last12), 2) AS cardiac_last12_pct,
  ROUND(100 * AVG(cardiac_first48) - 100 * AVG(cardiac_last12), 2) AS cardiac_diff_pp
FROM drug_exposure;