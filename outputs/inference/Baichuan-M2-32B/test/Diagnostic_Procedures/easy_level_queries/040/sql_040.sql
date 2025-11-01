WITH patients_filtered AS (
    SELECT 
        subject_id,
        anchor_year,
        anchor_age,
        DATE(anchor_year - anchor_age, 1, 1) AS birth_date
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
),
procedures_filtered AS (
    SELECT 
        p.subject_id,
        p.icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    INNER JOIN patients_filtered pt 
        ON p.subject_id = pt.subject_id
    WHERE 
        (LOWER(d.long_title) LIKE '%ecg%' OR LOWER(d.long_title) LIKE '%telemetry%')
        AND DATE_DIFF(p.chartdate, pt.birth_date, YEAR) BETWEEN 51 AND 61
),
patient_counts AS (
    SELECT 
        pt.subject_id,
        COUNT(DISTINCT p.icd_code) AS distinct_procedure_count
    FROM patients_filtered pt
    LEFT JOIN procedures_filtered p 
        ON pt.subject_id = p.subject_id
    GROUP BY pt.subject_id
)
SELECT 
    APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(25)] AS percentile_25
FROM patient_counts;