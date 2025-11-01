WITH target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),
proc_counts AS (
    SELECT tp.subject_id, COUNT(DISTINCT picd.icd_code) AS num_procedures
    FROM target_patients tp
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON tp.subject_id = picd.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON picd.icd_code = dicd.icd_code AND picd.icd_version = dicd.icd_version
    WHERE picd.icd_version = 10
    AND dicd.icd_code IN (
        '5A0211D', -- Assistance with Cardiac Output using Impella Device
        '5A0221D', -- Assistance with Cardiac Output using Intra-aortic Balloon Pump
        '02HA0RJ', -- Insertion of Intra-aortic Balloon Pump
        '5A15223', -- Extracorporeal Membrane Oxygenation
        '02HA0RS'  -- Insertion of other peripheral vascular device (e.g., VAD)
    )
    GROUP BY tp.subject_id
    HAVING num_procedures > 0  -- Only consider patients with at least one procedure
)
SELECT MIN(num_procedures) AS min_procedures_per_patient
FROM proc_counts;