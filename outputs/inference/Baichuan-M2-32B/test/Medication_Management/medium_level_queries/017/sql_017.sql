WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
        AND (dd.long_title LIKE 'Diabetes mellitus%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE 
        d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10'
        AND (
          d.icd_code IN (
            'I10', 'I11', 'I13', 'I25.1', 'I25.2', 'I25.3', 'I25.4', 'I25.5', 'I25.9', 
            'I42.0', 'I42.1', 'I42.2', 'I42.3', 'I42.4', 'I42.5', 'I42.6', 'I42.7', 'I42.8', 'I42.9', 
            'I50.0', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'
          )
          OR dd.long_title LIKE '%heart failure%' OR dd.long_title LIKE '%cardiomyopathy%' OR dd.long_title LIKE '%cardiac failure%'
        )
    )
),
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients e 
    ON i.subject_id = e.subject_id AND i.hadm_id = e.hadm_id
  WHERE 
    i.los >= 144  -- at least 144 hours (6 days)
),
prescriptions_during_icu AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN icu_stays i 
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
  WHERE 
    p.starttime <= i.outtime 
    AND (p.stoptime >= i.intime OR p.stoptime IS NULL)
),
classified_prescriptions AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    starttime,
    stoptime,
    intime,
    outtime,
    CASE
      WHEN drug LIKE '%insulin%' OR drug LIKE '%metformin%' OR drug LIKE '%glipizide%' OR drug LIKE '%glyburide%' OR drug LIKE '%glimepiride%' OR drug LIKE '%pioglitazone%' OR drug LIKE '%rosiglitazone%' OR drug LIKE '%sitagliptin%' OR drug LIKE '%saxagliptin%' OR drug LIKE '%alogliptin%' OR drug LIKE '%linagliptin%' OR drug LIKE '%empagliflozin%' OR drug LIKE '%canagliflozin%' OR drug LIKE '%dapagliflozin%' OR drug LIKE '%semaglutide%' OR drug LIKE '%liraglutide%' OR drug LIKE '%exenatide%' OR drug LIKE '%pramlintide%' THEN 'antidiabetics'
      WHEN drug LIKE '%metoprolol%' OR drug LIKE '%atenolol%' OR drug LIKE '%bisoprolol%' OR drug LIKE '%carvedilol%' OR drug LIKE '%propranolol%' OR drug LIKE '%labetalol%' OR drug LIKE '%esmolol%' OR drug LIKE '%nadolol%' OR drug LIKE '%pindolol%' OR drug LIKE '%acebutolol%' OR drug LIKE '%atenolol%' OR drug LIKE '%bucindolol%' OR drug LIKE '%nebivolol%' THEN 'beta_blockers'
      WHEN drug LIKE '%lisinopril%' OR drug LIKE '%losartan%' OR drug LIKE '%valsartan%' OR drug LIKE '%irbesartan%' OR drug LIKE '%candesartan%' OR drug LIKE '%telmisartan%' OR drug LIKE '%olmesartan%' OR drug LIKE '%telmisartan%' OR drug LIKE '%enalapril%' OR drug LIKE '%ramipril%' OR drug LIKE '%perindopril%' OR drug LIKE '%quailidopril%' OR drug LIKE '%fosinopril%' OR drug LIKE '%captopril%' OR drug LIKE '%benazepril%' OR drug LIKE '%trandolapril%' OR drug LIKE '%sacubitril%' OR drug LIKE '%valsartan%' OR drug LIKE '%sacubitril%' OR drug LIKE '%valsartan%' THEN 'acei_arb_arni'
      WHEN drug LIKE '%furosemide%' OR drug LIKE '%bumetanide%' OR drug LIKE '%torsemide%' OR drug LIKE '%ethacrynic acid%' OR drug LIKE '%bendroflumethiazide%' OR drug LIKE '%hydrochlorothiazide%' OR drug LIKE '%chlothiazide%' OR drug LIKE '%metolazone%' OR drug LIKE '%triamterene%' OR drug LIKE '%spironolactone%' OR drug LIKE '%eplerenone%' THEN 'loop_diuretics'
      ELSE NULL
    END AS med_class
  FROM prescriptions_during_icu
),
prescription_flags AS (
  SELECT 
    subject_id,
    med_class,
    drug,
    starttime,
    stoptime,
    intime,
    outtime,
    -- First 72h window: [intime, intime + 72 hours]
    (starttime <= TIMESTAMP_ADD(intime, INTERVAL 72 HOUR) 
      AND (stoptime >= intime OR stoptime IS NULL)
    ) AS in_first_72h,
    -- Final 72h window: [outtime - 72 hours, outtime]
    (starttime <= outtime 
      AND (stoptime >= TIMESTAMP_SUB(outtime, INTERVAL 72 HOUR) OR stoptime IS NULL)
    ) AS in_final_72h
  FROM classified_prescriptions
  WHERE med_class IS NOT NULL
),
per_patient_class_flags AS (
  SELECT 
    subject_id,
    med_class,
    MAX(CASE WHEN in_first_72h THEN 1 ELSE 0 END) AS flag_first,
    MAX(CASE WHEN in_final_72h THEN 1 ELSE 0 END) AS flag_final
  FROM prescription_flags
  GROUP BY subject_id, med_class
),
per_patient_class_status AS (
  SELECT 
    subject_id,
    med_class,
    flag_first,
    flag_final,
    (flag_first = 1 AND flag_final = 1) AS continued,
    (flag_first = 0 AND flag_final = 1) AS initiated,
    (flag_first = 1 AND flag_final = 0) AS discontinued
  FROM per_patient_class_flags
),
aggregate_per_class AS (
  SELECT 
    med_class,
    COUNT(DISTINCT subject_id) AS total_patients,
    SUM(CASE WHEN flag_first = 1 THEN 1 ELSE 0 END) AS count_first,
    SUM(CASE WHEN flag_final = 1 THEN 1 ELSE 0 END) AS count_final,
    SUM(CASE WHEN continued THEN 1 ELSE 0 END) AS count_continued,
    SUM(CASE WHEN initiated THEN 1 ELSE 0 END) AS count_initiated,
    SUM(CASE WHEN discontinued THEN 1 ELSE 0 END) AS count_discontinued,
    (SUM(CASE WHEN flag_first = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id)) AS pct_first,
    (SUM(CASE WHEN flag_final = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT subject_id)) AS pct_final
  FROM per_patient_class_status
  GROUP BY med_class
)
SELECT 
  med_class,
  total_patients,
  pct_first,
  pct_final,
  count_continued,
  count_initiated,
  count_discontinued
FROM aggregate_per_class
ORDER BY med_class;