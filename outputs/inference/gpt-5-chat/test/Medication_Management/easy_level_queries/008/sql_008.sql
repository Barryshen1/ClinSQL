WITH patient_base AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
      AND anchor_age BETWEEN 64 AND 74
),
presc_filtered AS (
    SELECT p.subject_id, pr.hadm_id,
           LOWER(pr.drug) AS drug_lower,
           DATE(pr.starttime) AS start_date,
           DATE(pr.stoptime) AS stop_date,
           SAFE_CAST(DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS INT64) AS duration_days
    FROM patient_base p
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON p.subject_id = pr.subject_id
    WHERE pr.starttime IS NOT NULL
      AND pr.stoptime IS NOT NULL
      AND LOWER(drug) LIKE '%aspirin%'
         OR LOWER(drug) LIKE '%clopidogrel%'
         OR LOWER(drug) LIKE '%prasugrel%'
         OR LOWER(drug) LIKE '%ticagrelor%'
         OR LOWER(drug) LIKE '%ticlopidine%'
),
drug_flags AS (
    SELECT hadm_id,
           SUM(CASE WHEN drug_lower LIKE '%aspirin%' THEN duration_days ELSE 0 END) AS aspirin_duration,
           SUM(CASE WHEN drug_lower LIKE '%clopidogrel%' 
                     OR drug_lower LIKE '%prasugrel%' 
                     OR drug_lower LIKE '%ticagrelor%'
                     OR drug_lower LIKE '%ticlopidine%' 
                    THEN duration_days ELSE 0 END) AS p2y12_duration
    FROM presc_filtered
    GROUP BY hadm_id
),
admissions_with_both AS (
    SELECT hadm_id,
           aspirin_duration + p2y12_duration AS total_antiplatelet_duration
    FROM drug_flags
    WHERE aspirin_duration > 0
      AND p2y12_duration > 0
)
SELECT 
  PERCENTILE_CONT(total_antiplatelet_duration, 0.5) OVER() AS median_antiplatelet_duration_days
FROM admissions_with_both;