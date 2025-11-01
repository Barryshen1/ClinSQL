WITH all_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M'
        AND anchor_age BETWEEN 56 AND 66
),
icu_procedures AS (
    SELECT
        pe.subject_id,
        CAST(pe.itemid AS STRING) AS itemid
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON pe.itemid = di.itemid
        AND (
            di.label LIKE '%IABP%'
            OR di.label LIKE '%ECMO%'
            OR di.label LIKE '%VAD%'
            OR di.label LIKE '%TandemHeart%'
            OR di.label LIKE '%CentriMag%'
            OR di.label LIKE '%Impella%'
            OR di.label LIKE '%mechanical circulatory support%'
        )
),
hosp_procedures AS (
    SELECT
        pi.subject_id,
        pi.icd_code AS itemid
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
        ON pi.icd_code = dip.icd_code
        AND pi.icd_version = dip.icd_version
        AND (
            dip.long_title LIKE '%IABP%'
            OR dip.long_title LIKE '%ECMO%'
            OR dip.long_title LIKE '%VAD%'
            OR dip.long_title LIKE '%TandemHeart%'
            OR dip.long_title LIKE '%CentriMag%'
            OR dip.long_title LIKE '%Impella%'
            OR dip.long_title LIKE '%mechanical circulatory support%'
        )
),
all_procedures AS (
    SELECT subject_id, itemid FROM icu_procedures
    UNION ALL
    SELECT subject_id, itemid FROM hosp_procedures
),
patient_counts AS (
    SELECT
        p.subject_id,
        COUNT(DISTINCT ap.itemid) AS num_procedures
    FROM all_patients p
    LEFT JOIN all_procedures ap
        ON p.subject_id = ap.subject_id
    GROUP BY p.subject_id
)
SELECT
    STDDEV(num_procedures) AS std_dev
FROM patient_counts;