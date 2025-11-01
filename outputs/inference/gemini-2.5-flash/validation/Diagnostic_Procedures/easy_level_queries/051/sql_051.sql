SELECT
    -- Calculate the 75th percentile of the distinct procedure counts
    PERCENTILE_CONT(distinct_ecg_telemetry_procedures, 0.75) OVER() AS percentile_75_distinct_ecg_telemetry_procedures
FROM
    (
        SELECT
            pd.subject_id,
            -- Count the number of distinct ECG/telemetry ICD codes for each patient
            COUNT(DISTINCT rp.icd_code) AS distinct_ecg_telemetry_procedures
        FROM
            (
                SELECT
                    p.subject_id
                FROM
                    `physionet-data.mimiciv_3_1_hosp.patients` p
                WHERE
                    p.gender = 'M'
                    AND p.anchor_age BETWEEN 41 AND 51 -- Patients aged 41 to 51
            ) AS pd -- PatientDemographics
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
            ON pd.subject_id = picd.subject_id
        INNER JOIN
            (
                SELECT
                    d.icd_code,
                    d.icd_version
                FROM
                    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
                WHERE
                    -- ICD-9 codes for diagnostic cardiovascular procedures, including ECG and telemetry
                    (d.icd_version = 9 AND d.icd_code LIKE '895%')
                    -- Specific ICD-10-PCS codes for multilead and single-lead cardiac conduction measurement (ECG)
                    OR (d.icd_version = 10 AND d.icd_code IN ('4A023BZ', '4A023NZ'))
            ) AS rp -- RelevantICDProcedures
            ON picd.icd_code = rp.icd_code AND picd.icd_version = rp.icd_version
        GROUP BY
            pd.subject_id
    );