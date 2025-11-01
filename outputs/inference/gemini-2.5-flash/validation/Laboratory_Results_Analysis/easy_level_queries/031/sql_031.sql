SELECT
    PERCENTILE_CONT(le.valuenum, 0.75) WITHIN GROUP (ORDER BY le.valuenum) AS p75_serum_potassium_discharge_day
FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON le.subject_id = adm.subject_id AND le.hadm_id = adm.hadm_id
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
    ON le.subject_id = p.subject_id
WHERE
    p.gender = 'M'
    AND le.itemid = 50971 -- Itemid for Potassium (Serum) from d_labitems
    AND DATE(le.charttime) = DATE(adm.dischtime)
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0 -- Filter out null or non-positive values for potassium
    AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu`.icustays icu
        WHERE icu.subject_id = p.subject_id
          AND icu.hadm_id = adm.hadm_id -- Ensures ICU stay within this specific admission
    );