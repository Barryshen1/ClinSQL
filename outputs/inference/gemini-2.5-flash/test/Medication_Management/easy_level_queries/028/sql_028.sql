WITH AdmissionsFiltered AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 44 AND 54
),
AntiplateletPrescriptionsCategorized AS (
    SELECT
        af.subject_id,
        af.hadm_id,
        px.pharmacy_id, -- Unique identifier for the prescription line item
        px.drug,
        px.starttime,
        px.stoptime,
        CASE
            WHEN LOWER(px.drug) LIKE '%aspirin%' OR LOWER(px.drug) LIKE '%asa%' OR LOWER(px.drug) LIKE '%acetylsalicylic acid%' THEN 'Aspirin'
            WHEN LOWER(px.drug) LIKE '%clopidogrel%' OR LOWER(px.drug) LIKE '%plavix%' THEN 'P2Y12_Inhibitor'
            WHEN LOWER(px.drug) LIKE '%ticagrelor%' OR LOWER(px.drug) LIKE '%brilinta%' THEN 'P2Y12_Inhibitor'
            WHEN LOWER(px.drug) LIKE '%prasugrel%' OR LOWER(px.drug) LIKE '%effient%' THEN 'P2Y12_Inhibitor'
            ELSE NULL
        END AS drug_category,
        DATE_DIFF(px.stoptime, px.starttime, DAY) AS duration_days
    FROM
        AdmissionsFiltered AS af
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS px
        ON af.subject_id = px.subject_id AND af.hadm_id = px.hadm_id
    WHERE
        (LOWER(px.drug) LIKE '%aspirin%' OR LOWER(px.drug) LIKE '%asa%' OR LOWER(px.drug) LIKE '%acetylsalicylic acid%'
        OR LOWER(px.drug) LIKE '%clopidogrel%' OR LOWER(px.drug) LIKE '%plavix%'
        OR LOWER(px.drug) LIKE '%ticagrelor%' OR LOWER(px.drug) LIKE '%brilinta%'
        OR LOWER(px.drug) LIKE '%prasugrel%' OR LOWER(px.drug) LIKE '%effient%')
        AND px.starttime IS NOT NULL
        AND px.stoptime IS NOT NULL
        AND px.stoptime >= px.starttime -- Ensures valid time range for duration calculation
),
DAPTPatients AS (
    SELECT DISTINCT
        t1.subject_id,
        t1.hadm_id
    FROM
        AntiplateletPrescriptionsCategorized AS t1
    INNER JOIN
        AntiplateletPrescriptionsCategorized AS t2
        ON t1.subject_id = t2.subject_id
        AND t1.hadm_id = t2.hadm_id
    WHERE
        t1.drug_category = 'Aspirin'
        AND t2.drug_category = 'P2Y12_Inhibitor'
        -- Check for overlap between Aspirin and P2Y12_Inhibitor prescriptions
        AND t1.starttime <= t2.stoptime
        AND t2.starttime <= t1.stoptime
)
SELECT
    STDDEV(apc.duration_days) AS sd_single_antiplatelet_duration_days
FROM
    AntiplateletPrescriptionsCategorized AS apc
INNER JOIN
    DAPTPatients AS dapt
    ON apc.subject_id = dapt.subject_id
    AND apc.hadm_id = dapt.hadm_id
WHERE
    apc.duration_days IS NOT NULL AND apc.duration_days >= 0 -- Ensure duration is non-null and non-negative
;