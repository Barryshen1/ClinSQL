SELECT MIN(ce.valuenum) AS min_heart_rate
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON ce.subject_id = a.subject_id AND ce.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON ce.itemid = di.itemid
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 44 AND 54
        AND di.label = 'Heart Rate'
        AND di.category = 'Vital Signs'
        AND ce.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0;