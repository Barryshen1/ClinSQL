WITH patient_cohort AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
tia_admissions AS (
    SELECT DISTINCT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE (
        (diag.icd_version = 9 AND diag.icd_code LIKE '435%') OR
        (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
    )
),
icu_los_per_admission AS (
    SELECT i.hadm_id,
           SUM(i.los) AS total_icu_los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    GROUP BY i.hadm_id
    HAVING total_icu_los BETWEEN 1 AND 7
),
imaging_procedures AS (
    SELECT proc.hadm_id,
           COUNT(*) AS imaging_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON proc.icd_code = dicd.icd_code AND proc.icd_version = dicd.icd_version
    WHERE LOWER(dicd.long_title) LIKE '%imaging%'
        OR LOWER(dicd.long_title) LIKE '%x-ray%'
        OR LOWER(dicd.long_title) LIKE '%ct%'
        OR LOWER(dicd.long_title) LIKE '%mri%'
        OR LOWER(dicd.long_title) LIKE '%ultrasound%'
    GROUP BY proc.hadm_id
),
categorized_admissions AS (
    SELECT ta.hadm_id,
           CASE
               WHEN il.total_icu_los BETWEEN 1 AND 3 THEN '1-3 days'
               WHEN il.total_icu_los BETWEEN 4 AND 7 THEN '4-7 days'
           END AS los_category,
           COALESCE(ip.imaging_count, 0) AS imaging_count
    FROM tia_admissions ta
    INNER JOIN patient_cohort pc ON ta.subject_id = pc.subject_id
    INNER JOIN icu_los_per_admission il ON ta.hadm_id = il.hadm_id
    LEFT JOIN imaging_procedures ip ON ta.hadm_id = ip.hadm_id
)
SELECT los_category,
       AVG(imaging_count) AS mean_imaging_procedures,
       MIN(imaging_count) AS min_imaging_procedures,
       MAX(imaging_count) AS max_imaging_procedures,
       COUNT(*) AS num_admissions
FROM categorized_admissions
GROUP BY los_category
ORDER BY los_category;