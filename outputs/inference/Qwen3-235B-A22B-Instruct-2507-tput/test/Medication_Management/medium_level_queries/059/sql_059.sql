WITH patients_with_conditions AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
      d.icd_code LIKE 'E11%' 
      OR LOWER(d.long_title) LIKE '%type 2%diabetes%'
    )
  INTERSECT
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND (
      LOWER(d.long_title) LIKE '%heart failure%'
      OR d.icd_code IN ('I50', 'I50.9', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I11.0', 'I13.0')
    )
),
icu_stays_with_timing AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN patients_with_conditions p ON i.subject_id = p.subject_id
),
drug_exposure AS (
  SELECT
    i.subject_id,
    i.stay_id,
    -- First 48h initiation: drug started within 48h of ICU intime
    MAX(CASE 
      WHEN pr.starttime >= i.intime 
       AND pr.starttime <= i.intime + INTERVAL '48' HOUR
       AND (
        LOWER(pr.drug) IN (
          'insulin', 'insulin aspart', 'insulin glargine', 'insulin lispro',
          'metformin', 'glipizide', 'glyburide', 'sitagliptin', 'linagliptin',
          'exenatide', 'liraglutide', 'dulaglutide', 'semaglutide'
        ) OR LOWER(pr.drug) LIKE '%metformin%' 
          OR LOWER(pr.drug) LIKE '%gli%' 
          OR LOWER(pr.drug) LIKE '%glitaz%'
          OR LOWER(pr.drug) LIKE '%gliptin%'
          OR LOWER(pr.drug) LIKE '%insulin%'
       )
      THEN 1 ELSE 0 END) AS initiated_antidiabetic_48h,
    MAX(CASE 
      WHEN pr.starttime >= i.intime 
       AND pr.starttime <= i.intime + INTERVAL '48' HOUR
       AND (
        LOWER(pr.drug) IN (
          'metoprolol', 'carvedilol', 'bisoprolol', 'atenolol', 'nadolol', 'propranolol'
        ) OR LOWER(pr.drug) LIKE '%metoprolol%'
          OR LOWER(pr.drug) LIKE '%carvedilol%'
          OR LOWER(pr.drug) LIKE '%bisoprolol%'
          OR LOWER(pr.drug) LIKE '%atenolol%'
       )
      THEN 1 ELSE 0 END) AS initiated_beta_blocker_48h,
    MAX(CASE 
      WHEN pr.starttime >= i.intime 
       AND pr.starttime <= i.intime + INTERVAL '48' HOUR
       AND (
        LOWER(pr.drug) IN (
          'lisinopril', 'enalapril', 'ramipril', 'captopril',
          'losartan', 'valsartan', 'irbesartan', 'olmesartan', 'candesartan',
          'sacubitril/valsartan'
        ) OR LOWER(pr.drug) LIKE '%lisinopril%'
          OR LOWER(pr.drug) LIKE '%enalapril%'
          OR LOWER(pr.drug) LIKE '%ramipril%'
          OR LOWER(pr.drug) LIKE '%losartan%'
          OR LOWER(pr.drug) LIKE '%valsartan%'
          OR LOWER(pr.drug) LIKE '%sacubitril%'
       )
      THEN 1 ELSE 0 END) AS initiated_acei_arb_arni_48h,
    MAX(CASE 
      WHEN pr.starttime >= i.intime 
       AND pr.starttime <= i.intime + INTERVAL '48' HOUR
       AND (
        LOWER(pr.drug) IN ('furosemide', 'bumetanide', 'torsemide')
        OR LOWER(pr.drug) LIKE '%furosemide%'
        OR LOWER(pr.drug) LIKE '%bumetanide%'
        OR LOWER(pr.drug) LIKE '%torsemide%'
       )
      THEN 1 ELSE 0 END) AS initiated_loop_diuretic_48h,
    -- Final 24h presence: drug active in last 24h of ICU stay
    MAX(CASE 
      WHEN pr.starttime <= i.outtime
       AND (pr.stoptime IS NULL OR pr.stoptime >= i.outtime - INTERVAL '24' HOUR)
       AND (
        LOWER(pr.drug) IN (
          'insulin', 'insulin aspart', 'insulin glargine', 'insulin lispro',
          'metformin', 'glipizide', 'glyburide', 'sitagliptin', 'linagliptin',
          'exenatide', 'liraglutide', 'dulaglutide', 'semaglutide'
        ) OR LOWER(pr.drug) LIKE '%metformin%' 
          OR LOWER(pr.drug) LIKE '%gli%' 
          OR LOWER(pr.drug) LIKE '%glitaz%'
          OR LOWER(pr.drug) LIKE '%gliptin%'
          OR LOWER(pr.drug) LIKE '%insulin%'
       )
      THEN 1 ELSE 0 END) AS on_antidiabetic_final_24h,
    MAX(CASE 
      WHEN pr.starttime <= i.outtime
       AND (pr.stoptime IS NULL OR pr.stoptime >= i.outtime - INTERVAL '24' HOUR)
       AND (
        LOWER(pr.drug) IN (
          'metoprolol', 'carvedilol', 'bisoprolol', 'atenolol', 'nadolol', 'propranolol'
        ) OR LOWER(pr.drug) LIKE '%metoprolol%'
          OR LOWER(pr.drug) LIKE '%carvedilol%'
          OR LOWER(pr.drug) LIKE '%bisoprolol%'
          OR LOWER(pr.drug) LIKE '%atenolol%'
       )
      THEN 1 ELSE 0 END) AS on_beta_blocker_final_24h,
    MAX(CASE 
      WHEN pr.starttime <= i.outtime
       AND (pr.stoptime IS NULL OR pr.stoptime >= i.outtime - INTERVAL '24' HOUR)
       AND (
        LOWER(pr.drug) IN (
          'lisinopril', 'enalapril', 'ramipril', 'captopril',
          'losartan', 'valsartan', 'irbesart;