WITH med_classes AS (
  SELECT 'Antidiabetic' AS class, drug_name
  FROM UNNEST(['insulin', 'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone', 'sitagliptin', 'saxagliptin', 'linagliptin', 'exenatide', 'liraglutide', 'dulaglutide', 'semaglutide', 'canagliflozin', 'dapagliflozin', 'empagliflozin']) AS drug_name
  UNION ALL
  SELECT 'Beta-blocker', drug_name
  FROM UNNEST(['propranolol', 'metoprolol', 'atenolol', 'bisoprolol', 'carvedilol', 'labetalol', 'nebivolol']) AS drug_name
  UNION ALL
  SELECT 'ACEi/ARB/ARNI', drug_name
  FROM UNNEST(['captopril', 'enalapril', 'lisinopril', 'ramipril', 'quinapril', 'benazepril', 'fosinopril', 'moexipril', 'perindopril', 'trandolapril', 'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'azilsartan', 'sacubitril/valsartan', 'sacubitril valsartan']) AS drug_name
  UNION ALL
  SELECT 'Loop diuretic', drug_name
  FROM UNNEST(['furosemide', 'bumetanide', 'torsemide']) AS drug_name
),
classes AS (
  SELECT DISTINCT class FROM med_classes
),
cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.subject_id = a.subject_id 
        AND diag.hadm_id = a.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%') 
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E1%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE 
        diag.subject_id = a.subject_id 
        AND diag.hadm_id = a.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),
first_prescriptions AS (
  SELECT 
    c.hadm_id, 
    mc.class,
    MIN(p.starttime) AS first_starttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  INNER JOIN med_classes mc
    ON LOWER(p.drug) LIKE CONCAT('%', LOWER(mc.drug_name), '%')
  GROUP BY c.hadm_id, mc.class
),
admission_classes AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    cls.class
  FROM cohort c
  CROSS JOIN classes cls
),
class_indicators AS (
  SELECT 
    ac.hadm_id,
    ac.class,
    ac.admittime,
    ac.dischtime,
    fp.first_starttime,
    CASE 
      WHEN fp.first_starttime IS NOT NULL 
        AND fp.first_starttime BETWEEN ac.admittime 
        AND LEAST(DATETIME_ADD(ac.admittime, INTERVAL 48 HOUR), ac.dischtime) 
      THEN 1 
      ELSE 0 
    END AS in_first_48h,
    CASE 
      WHEN fp.first_starttime IS NOT NULL 
        AND fp.first_starttime BETWEEN GREATEST(DATETIME_SUB(ac.dischtime, INTERVAL 12 HOUR), ac.admittime) 
        AND ac.dischtime 
      THEN 1 
      ELSE 0 
    END AS in_last_12h
  FROM admission_classes ac
  LEFT JOIN first_prescriptions fp
    ON ac.hadm_id = fp.hadm_id AND ac.class = fp.class
)
SELECT 
  class,
  COUNT(hadm_id) AS total_admissions,
  SUM(in_first_48h) AS count_first_48h,
  SUM(in_last_12h) AS count_last_12h,
  ROUND(SUM(in_first_48h) * 100.0 / COUNT(hadm_id), 2) AS rate_first_48h,
  ROUND(SUM(in_last_12h) * 100.0 / COUNT(hadm_id), 2) AS rate_last_12h,
  ROUND(
    (SUM(in_last_12h) * 100.0 / COUNT(hadm_id)) - 
    (SUM(in_first_48h) * 100.0 / COUNT(hadm_id)), 
    2
  ) AS net_change
FROM class_indicators
GROUP BY class
ORDER BY class;