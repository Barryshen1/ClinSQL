WITH population AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.icd_code LIKE 'I50%'
    )
),

prescriptions_filtered AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.drug
  FROM population p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON p.hadm_id = pr.hadm_id
  WHERE pr.starttime >= p.admittime
    AND pr.starttime <= p.dischtime
),

medication_classes AS (
  SELECT 
    subject_id,
    hadm_id,
    starttime,
    CASE 
      WHEN drug LIKE '%insulin%' OR drug LIKE '%metformin%' OR drug LIKE '%glipizide%' OR drug LIKE '%glyburide%' OR 
           drug LIKE '%sitagliptin%' OR drug LIKE '%empagliflozin%' OR drug LIKE '%exenatide%' OR drug LIKE '%liraglutide%' OR 
           drug LIKE '%dulaglutide%' OR drug LIKE '%semaglutide%' OR drug LIKE '%pioglitazone%' OR drug LIKE '%repaglinide%' OR 
           drug LIKE '%nateglinide%' OR drug LIKE '%canagliflozin%' OR drug LIKE '%dapagliflozin%' THEN 'antidiabetic'
      WHEN drug LIKE '%metoprolol%' OR drug LIKE '%atenolol%' OR drug LIKE '%propranolol%' OR drug LIKE '%carvedilol%' OR 
           drug LIKE '%bisoprolol%' OR drug LIKE '%nebivolol%' OR drug LIKE '%labetalol%' THEN 'beta_blocker'
      WHEN drug LIKE '%lisinopril%' OR drug LIKE '%enalapril%' OR drug LIKE '%ramipril%' OR drug LIKE '%captopril%' OR 
           drug LIKE '%quinapril%' OR drug LIKE '%perindopril%' OR drug LIKE '%benazepril%' OR 
           drug LIKE '%losartan%' OR drug LIKE '%valsartan%' OR drug LIKE '%irbesartan%' OR drug LIKE '%telmisartan%' OR 
           drug LIKE '%candesartan%' OR drug LIKE '%olmesartan%' OR 
           drug LIKE '%sacubitril%' OR drug LIKE '%entresto%' THEN 'acei_arb_arni'
      WHEN drug LIKE '%furosemide%' OR drug LIKE '%bumetanide%' OR drug LIKE '%torsemide%' THEN 'loop_diuretic'
      ELSE NULL
    END AS class
  FROM prescriptions_filtered
),

medication_flags AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    MAX(CASE WHEN mc.class = 'antidiabetic' AND mc.starttime >= p.admittime AND mc.starttime <= p.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS antidiabetic_first_48h,
    MAX(CASE WHEN mc.class = 'antidiabetic' AND mc.starttime >= p.dischtime - INTERVAL '24' HOUR AND mc.starttime <= p.dischtime THEN 1 ELSE 0 END) AS antidiabetic_final_24h,
    MAX(CASE WHEN mc.class = 'beta_blocker' AND mc.starttime >= p.admittime AND mc.starttime <= p.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS beta_blocker_first_48h,
    MAX(CASE WHEN mc.class = 'beta_blocker' AND mc.starttime >= p.dischtime - INTERVAL '24' HOUR AND mc.starttime <= p.dischtime THEN 1 ELSE 0 END) AS beta_blocker_final_24h,
    MAX(CASE WHEN mc.class = 'acei_arb_arni' AND mc.starttime >= p.admittime AND mc.starttime <= p.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS acei_arb_arni_first_48h,
    MAX(CASE WHEN mc.class = 'acei_arb_arni' AND mc.starttime >= p.dischtime - INTERVAL '24' HOUR AND mc.starttime <= p.dischtime THEN 1 ELSE 0 END) AS acei_arb_arni_final_24h,
    MAX(CASE WHEN mc.class = 'loop_diuretic' AND mc.starttime >= p.admittime AND mc.starttime <= p.admittime + INTERVAL '48' HOUR THEN 1 ELSE 0 END) AS loop_diuretic_first_48h,
    MAX(CASE WHEN mc.class = 'loop_diuretic' AND mc.starttime >= p.dischtime - INTERVAL '24' HOUR AND mc.starttime <= p.dischtime THEN 1 ELSE 0 END) AS loop_diuretic_final_24h
  FROM population p
  LEFT JOIN medication_classes mc ON p.hadm_id = mc.hadm_id
  GROUP BY p.subject_id, p.hadm_id
)

SELECT 
  'antidiabetic' AS medication_class,
  AVG(antidiabetic_first_48h) * 100 AS first_48h_percent,
  AVG(antidiabetic_final_24h) * 100 AS final_24h_percent,
  (AVG(antidiabetic_final_24h) - AVG(antidiabetic_first_48h)) * 100 AS absolute_difference
FROM medication_flags
UNION ALL
SELECT 
  'beta_blocker',
  AVG(beta_blocker_first_48h) * 100,
  AVG(beta_blocker_final_24h) * 100,
  (AVG(beta_blocker_final_24h) - AVG(beta_blocker_first_48h)) * 100
FROM medication_flags
UNION ALL
SELECT 
  'acei_arb_arni',
  AVG(acei_arb_arni_first_48h) * 100,
  AVG(acei_arb_arni_final_24h) * 100,
  (AVG(acei_arb_arni_final_24h) - AVG(acei_arb_arni_first_48h)) * 100
FROM medication_flags
UNION ALL
SELECT 
  'loop_diuretic',
  AVG(loop_diuretic_first_48h) * 100,
  AVG(loop_diuretic_final_24h) * 100,
  (AVG(loop_diuretic_final_24h) - AVG(loop_diuretic_first_48h)) * 100
FROM medication_flags;