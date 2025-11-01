WITH admissions_with_age AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        p.anchor_age,
        p.anchor_year,
        EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
),
qualifying_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id
    FROM admissions_with_age a
    WHERE a.age_at_admission BETWEEN 64 AND 74
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
            WHERE pr.subject_id = a.subject_id 
                AND pr.hadm_id = a.hadm_id
                AND pr.drug IN ('Aspirin', 'ASA', 'acetylsalicylic acid')
        )
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
            WHERE pr.subject_id = a.subject_id 
                AND pr.hadm_id = a.hadm_id
                AND pr.drug IN ('Clopidogrel', 'Prasugrel', 'Ticagrelor', 'Cangrelor')
        )
),
antiplatelet_prescriptions AS (
    SELECT 
        pr.subject_id,
        pr.hadm_id,
        pr.starttime,
        COALESCE(pr.stoptime, a.dischtime) AS endtime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON pr.subject_id = a.subject_id AND pr.hadm_id = a.hadm_id
    JOIN qualifying_admissions qa 
        ON pr.subject_id = qa.subject_id AND pr.hadm_id = qa.hadm_id
    WHERE pr.drug IN (
        'Aspirin', 'ASA', 'acetylsalicylic acid', 
        'Clopidogrel', 'Prasugrel', 'Ticagrelor', 'Cangrelor'
    )
),
patient_durations AS (
    SELECT 
        subject_id,
        hadm_id,
        MIN(starttime) AS first_start,
        MAX(endtime) AS last_end
    FROM antiplatelet_prescriptions
    GROUP BY subject_id, hadm_id
)
SELECT 
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(last_end, first_start, DAY)) AS median_duration
FROM patient_durations;