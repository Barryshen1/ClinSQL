WITH eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 41 AND 51
),
icu_procedure_counts AS (
    SELECT 
        ep.subject_id,
        COUNT(DISTINCT pe.itemid) AS icu_procedure_count
    FROM eligible_patients ep
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON ep.subject_id = pe.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON pe.itemid = di.itemid
    WHERE di.label LIKE '%ECG%' 
        OR di.label LIKE '%EKG%' 
        OR di.label LIKE '%Telemetry%'
    GROUP BY ep.subject_id
),
hosp_procedure_counts AS (
    SELECT 
        ep.subject_id,
        COUNT(DISTINCT pi.icd_code) AS hosp_procedure_count
    FROM eligible_patients ep
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi 
        ON ep.subject_id = pi.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
        ON pi.icd_code = dip.icd_code 
        AND pi.icd_version = dip.icd_version
    WHERE dip.long_title LIKE '%ECG%' 
        OR dip.long_title LIKE '%EKG%' 
        OR dip.long_title LIKE '%Telemetry%'
    GROUP BY ep.subject_id
),
total_counts AS (
    SELECT 
        ep.subject_id,
        COALESCE(ipc.icu_procedure_count, 0) + 
        COALESCE(hpc.hosp_procedure_count, 0) AS total_procedures
    FROM eligible_patients ep
    LEFT JOIN icu_procedure_counts ipc 
        ON ep.subject_id = ipc.subject_id
    LEFT JOIN hosp_procedure_counts hpc 
        ON ep.subject_id = hpc.subject_id
)
SELECT 
    APPROX_QUANTILES(total_procedures, 100)[OFFSET(75)] AS percentile_75
FROM total_counts;