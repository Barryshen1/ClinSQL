WITH patient_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 76 AND 86
),
cardiac_procedures AS (
    SELECT pi.subject_id, pi.hadm_id, pi.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
    WHERE dip.long_title LIKE '%cardiac%' OR dip.long_title LIKE '%heart%'
),
counts_per_admission AS (
    SELECT 
        pa.hadm_id,
        COUNT(DISTINCT cp.icd_code) AS num_cardiac_procedures
    FROM patient_admissions pa
    LEFT JOIN cardiac_procedures cp
        ON pa.hadm_id = cp.hadm_id
    GROUP BY pa.hadm_id
)
SELECT 
    APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(75)] - APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(25)] AS iqr
FROM counts_per_admission;