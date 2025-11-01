WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
),
dx_flags AS (
  SELECT hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '250%')
              OR (icd_version = 10 AND icd_code LIKE 'E0%' AND SUBSTR(icd_code,1,3) BETWEEN 'E08' AND 'E13')
             THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN (icd_version = 9 AND icd_code LIKE '428%')
              OR (icd_version = 10 AND icd_code LIKE 'I50%')
             THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
eligible AS (
  SELECT c.*
  FROM cohort c
  JOIN dx_flags d
    ON c.hadm_id = d.hadm_id
  WHERE d.has_diabetes = 1
    AND d.has_hf = 1
),
classified_meds AS (
  SELECT pr.hadm_id, 
         pr.starttime,
         CASE
           WHEN LOWER(pr.drug) LIKE '%insulin%' 
             OR LOWER(pr.drug) LIKE 'metformin%' 
             OR LOWER(pr.drug) LIKE 'glipizide%' 
             OR LOWER(pr.drug) LIKE 'glyburide%' 
             OR LOWER(pr.drug) LIKE 'pioglitazone%' 
             OR LOWER(pr.drug) LIKE 'sitagliptin%' 
                THEN 'Antidiabetic'
           WHEN LOWER(pr.drug) LIKE '%metoprolol%' 
             OR LOWER(pr.drug) LIKE '%atenolol%' 
             OR LOWER(pr.drug) LIKE '%propranolol%' 
             OR LOWER(pr.drug) LIKE '%carvedilol%' 
             OR LOWER(pr.drug) LIKE '%bisoprolol%' 
                THEN 'Beta-blocker'
           WHEN LOWER(pr.drug) LIKE '%lisinopril%' 
             OR LOWER(pr.drug) LIKE '%enalapril%' 
             OR LOWER(pr.drug) LIKE '%ramipril%' 
             OR LOWER(pr.drug) LIKE '%captopril%' 
             OR LOWER(pr.drug) LIKE '%quinapril%' 
             OR LOWER(pr.drug) LIKE '%valsartan%' 
             OR LOWER(pr.drug) LIKE '%losartan%' 
             OR LOWER(pr.drug) LIKE '%sacubitril%' 
             OR LOWER(pr.drug) LIKE '%candesar%' 
                THEN 'ACEi/ARB/ARNI'
           WHEN LOWER(pr.drug) LIKE '%furosemide%' 
             OR LOWER(pr.drug) LIKE '%bumetanide%' 
             OR LOWER(pr.drug) LIKE '%torsemide%'
                THEN 'Loop diuretic'
         END AS med_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE pr.starttime IS NOT NULL
),
first_admin AS (
  SELECT e.hadm_id, cm.med_class, MIN(cm.starttime) AS first_time
  FROM eligible e
  JOIN classified_meds cm
    ON e.hadm_id = cm.hadm_id
  WHERE cm.med_class IS NOT NULL
  GROUP BY e.hadm_id, cm.med_class
),
timed_flags AS (
  SELECT fa.med_class,
         COUNTIF(fa.first_time <= e.admittime + INTERVAL 48 HOUR) AS early_count,
         COUNTIF(fa.first_time >= e.dischtime - INTERVAL 12 HOUR) AS late_count,
         COUNT(*) AS total_with_medclass
  FROM first_admin fa
  JOIN eligible e
    ON fa.hadm_id = e.hadm_id
  GROUP BY fa.med_class
),
results AS (
  SELECT med_class,
         100.0 * early_count / total_with_medclass AS early_rate,
         100.0 * late_count / total_with_medclass AS late_rate,
         100.0 * (early_count - late_count) / total_with_medclass AS net_change
  FROM timed_flags
)
SELECT med_class, early_rate, late_rate, net_change
FROM results
ORDER BY med_class;