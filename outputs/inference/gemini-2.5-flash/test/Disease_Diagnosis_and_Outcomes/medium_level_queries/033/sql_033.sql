WITH PatientAdmissionData AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS hosp_los_days,
        ad.hospital_expire_flag,
        CASE
            WHEN EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = ad.hadm_id) THEN 'ICU'
            ELSE 'Non-ICU'
        END AS icu_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 82 AND 92
),
-- Step 2: Identify admissions with postoperative complications
PostOpComplications AS (
    SELECT DISTINCT
        dd.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dd
    WHERE
        (dd.icd_version = 10 AND dd.icd_code LIKE 'T8[0-8]%') -- ICD-10: Complications of surgical and medical care
        OR (dd.icd_version = 9 AND dd.icd_code LIKE '99[6-9]%') -- ICD-9: Complications of medical and surgical care
),
-- Step 3: Filter PatientAdmissionData to include only those with complications
AdmissionsWithComplications AS (
    SELECT
        pad.*
    FROM
        PatientAdmissionData pad
    INNER JOIN
        PostOpComplications poc
        ON pad.hadm_id = poc.hadm_id
),
-- Step 4: Calculate comorbidity count for each relevant admission
ComorbidityCounts AS (
    SELECT
        ac.hadm_id,
        COUNT(DISTINCT di.icd_code) AS comorbidity_count
    FROM
        AdmissionsWithComplications ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ac.hadm_id = di.hadm_id
    WHERE
        -- Exclude the post-operative complication codes themselves from the comorbidity count
        NOT (
            (di.icd_version = 10 AND di.icd_code LIKE 'T8[0-8]%')
            OR (di.icd_version = 9 AND di.icd_code LIKE '99[6-9]%')
        )
    GROUP BY
        ac.hadm_id
)
-- Step 5: Final selection, binning, and aggregation
SELECT
    final.icu_status,
    final.los_bin,
    final.comorbidity_bin,
    COUNT(final.hadm_id) AS N, -- N refers to the number of qualifying admissions
    ROUND(AVG(final.hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
    ROUND(AVG(final.comorbidity_count), 2) AS average_comorbidity_count
FROM (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.icu_status,
        ac.hospital_expire_flag,
        -- Use COALESCE to assign 0 if no other comorbidities are found for the admission
        COALESCE(cc.comorbidity_count, 0) AS comorbidity_count,
        CASE
            WHEN ac.hosp_los_days <= 5 THEN 'LOS <= 5'
            ELSE 'LOS > 5'
        END AS los_bin,
        CASE
            WHEN COALESCE(cc.comorbidity_count, 0) <= 1 THEN '0-1 Comorbidity'
            WHEN COALESCE(cc.comorbidity_count, 0) = 2 THEN '2 Comorbidities'
            ELSE '>= 3 Comorbidities'
        END AS comorbidity_bin
    FROM
        AdmissionsWithComplications ac
    LEFT JOIN
        ComorbidityCounts cc
        ON ac.hadm_id = cc.hadm_id
) final
GROUP BY
    final.icu_status,
    final.los_bin,
    final.comorbidity_bin
ORDER BY
    final.icu_status,
    final.los_bin,
    final.comorbidity_bin;