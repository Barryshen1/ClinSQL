SELECT
    AVG(total_icu_los_days) AS mean_icu_los_days
FROM (
    -- Step 4: Calculate total ICU LOS for the first CABG admission of each eligible patient
    SELECT
        pfc.subject_id,
        pfc.hadm_id,
        SUM(icu.los) AS total_icu_los_days
    FROM (
        -- Step 3: Identify the first CABG admission for each eligible patient
        SELECT
            pa.subject_id,
            ad.hadm_id,
            ROW_NUMBER() OVER (PARTITION BY pa.subject_id ORDER BY ad.admittime) as rn
        FROM
            `physionet-data.mimiciv_3_1_hosp`.patients pa
        JOIN
            `physionet-data.mimiciv_3_1_hosp`.admissions ad
            ON pa.subject_id = ad.subject_id
        JOIN
            `physionet-data.mimiciv_3_1_hosp`.procedures_icd picd
            ON ad.subject_id = picd.subject_id AND ad.hadm_id = picd.hadm_id
        JOIN
            `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dp
            ON picd.icd_code = dp.icd_code AND picd.icd_version = dp.icd_version
        WHERE
            pa.gender = 'M'
            AND pa.anchor_age BETWEEN 74 AND 84
            -- Step 1: Filter for CABG related procedures
            AND UPPER(dp.long_title) LIKE '%CORONARY ARTERY BYPASS%'
    ) AS pfc
    JOIN
        `physionet-data.mimiciv_3_1_icu`.icustays icu
        ON pfc.subject_id = icu.subject_id AND pfc.hadm_id = icu.hadm_id
    WHERE
        pfc.rn = 1 -- Only consider the very first CABG admission per patient
    GROUP BY
        pfc.subject_id,
        pfc.hadm_id
);