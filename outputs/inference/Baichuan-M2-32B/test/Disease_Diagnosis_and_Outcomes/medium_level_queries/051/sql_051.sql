SELECT
        a.hadm_id,
        CASE WHEN MAX(i.stay_id IS NOT NULL) THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
    FROM postoperative_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
        ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
    GROUP BY a.hadm_id;