SELECT
    MIN(DATE_DIFF(ad.dischtime, ad.admittime, DAY)) AS shortest_inpatient_duration_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON ad.subject_id = pat.subject_id
JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    ON ad.subject_id = pres.subject_id AND ad.hadm_id = pres.hadm_id
WHERE
    pat.gender = 'F'
    -- Calculate age at admission and filter for the 81-91 range
    AND (pat.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
    -- Filter for the specified medications
    AND (LOWER(pres.drug) LIKE '%hydralazine%' OR LOWER(pres.drug) LIKE '%isosorbide dinitrate%');